import Foundation
import Observation
import GRDB

@MainActor
@Observable
final class AppState {
    var database: AppDatabase
    var databaseURL: URL?
    private(set) var launchError: String?

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

    func resetDatabase(seed: Bool) throws {
        try database.dbQueue.write { db in
            let tables = [
                "stockMovements", "dispatchDetails", "invoiceItems", "salesInvoices",
                "productionItems", "productionBatches", "payments", "purchases",
                "productRates", "vehicles", "suppliers", "customers", "products",
                "appSettings",
            ]
            for table in tables {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
        if seed {
            try database.dbQueue.write { db in try DemoSeeder.seed(db: db) }
        }
    }
}