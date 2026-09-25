import Foundation
import Observation
import GRDB

/// A deferred intention to record a customer payment, carried across modules
/// (e.g. "record payment against this invoice" from the Sales screen).
struct PaymentDraft: Equatable {
    var customerId: Int64
    var invoiceId: Int64?
    var amountHintPaise: Int64?
}

@MainActor
@Observable
final class AppState {
    var database: AppDatabase
    var databaseURL: URL?
    private(set) var launchError: String?
    var dataEpoch: Int = 0

    // MARK: Cross-module navigation

    var selectedDestination: SidebarDestination? = .overview

    /// Set by Sales when the user asks to record a payment against an invoice;
    /// consumed by Payments which opens the payment editor pre-filled.
    var pendingPaymentDraft: PaymentDraft?

    func recordPayment(draft: PaymentDraft) {
        pendingPaymentDraft = draft
        selectedDestination = .payments
    }

    init() {
        do {
            let url = try AppDatabase.defaultDatabaseURL()
            let db = try AppDatabase.open(at: url)
            try DemoSeeder.seedIfNeeded(db.dbQueue)
            self.database = db
            self.databaseURL = url
        } catch {
            self.database = AppDatabase.inMemory()
            self.databaseURL = nil
            self.launchError = error.localizedDescription
        }
    }

    init(database: AppDatabase, databaseURL: URL?) {
        self.database = database
        self.databaseURL = databaseURL
    }

    /// Re-attempts opening the on-disk database after a launch failure, so the
    /// user can recover from the blocking error screen without quitting.
    @MainActor
    func retryOpen() {
        do {
            let url = try AppDatabase.defaultDatabaseURL()
            let db = try AppDatabase.open(at: url)
            try DemoSeeder.seedIfNeeded(db.dbQueue)
            self.database = db
            self.databaseURL = url
            self.launchError = nil
            self.dataEpoch += 1
        } catch {
            self.launchError = error.localizedDescription
        }
    }

    func resetDatabase(seed: Bool) async throws {
        try await database.dbQueue.write { db in
            let tables = [
                "stockMovements", "dispatchDetails", "invoiceItems", "salesInvoices",
                "productionItems", "productionBatches", "payments", "purchases",
                "productRates", "vehicles", "suppliers", "customers", "products",
                "appSettings",
            ]
            for table in tables {
                try db.execute(sql: "DELETE FROM \(table)")
            }
            if !seed {
                // The seed flag lives in appSettings, which was just cleared;
                // re-arm it so the demo dataset is not silently written back
                // into this now-empty database on the next launch.
                try AppSetting.set(key: "first_launch_seeded", value: "1", db: db)
            }
        }
        if seed {
            try await database.dbQueue.write { db in try DemoSeeder.seed(db: db) }
        }
        dataEpoch += 1
    }

    /// Validates `backupURL`, swaps it in for the live database file, then
    /// reopens the database so every screen reads from the restored data.
    func restoreBackup(from backupURL: URL) throws {
        try BackupRestore.validateBackup(at: backupURL)
        guard let url = databaseURL else {
            throw BackupRestoreError.invalidFile("The live database is not available for restore.")
        }
        // The live queue is closed inside `replace` before the file is swapped.
        // If reopening the restored file fails we must never keep serving
        // writes through the closed connection (they would silently vanish),
        // so the app falls back to the blocking launch-error screen instead.
        try BackupRestore.replace(databaseURL: url, with: backupURL, closing: database.dbQueue)
        do {
            database = try AppDatabase.open(at: url)
        } catch {
            launchError = "The backup was restored but could not be reopened: \(error.localizedDescription)"
            dataEpoch += 1
            throw error
        }
        dataEpoch += 1
    }
}