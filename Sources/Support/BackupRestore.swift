import Foundation
import GRDB

/// Validation and file-swap logic for restoring a database from a backup file.
enum BackupRestore {
    /// All application tables that must exist in a valid PaashERP database.
    static let expectedTables = [
        "stockMovements", "dispatchDetails", "invoiceItems", "salesInvoices",
        "productionItems", "productionBatches", "payments", "purchases",
        "productRates", "vehicles", "suppliers", "customers", "products",
        "appSettings",
    ]

    /// Schema versions this app can migrate backwards from: the identifiers of
    /// the migrations it knows about. Backups carrying any identifier outside
    /// this set were created by a newer app and are rejected rather than
    /// guessed at.
    static var supportedSchemaVersions: Set<String> {
        Set(AppDatabase.migrator.migrations)
    }

    /// Creates a crash-consistent copy of the live database via SQLite's
    /// Online Backup API. The produced file is exactly one committed database
    /// state even if writes happen while the copy runs — unlike a raw
    /// `Data(contentsOf:)` read of a database in rollback-journal mode, which
    /// can observe a torn, half-transactional state.
    static func createBackup(from queue: DatabaseQueue, to destinationURL: URL) throws {
        do {
            let backupQueue = try DatabaseQueue(path: destinationURL.path)
            try queue.backup(to: backupQueue)
            try backupQueue.close()
        } catch {
            throw BackupRestoreError.backupFailed(
                "The database backup could not be created: \(error.localizedDescription)"
            )
        }
    }

    /// Opens the file read-only and verifies it is a healthy PaashERP database:
    /// readable, contains every expected table, knows a schema version this app
    /// can restore, and passes `PRAGMA quick_check`.
    static func validateBackup(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BackupRestoreError.invalidFile("The selected file does not exist.")
        }
        var configuration = Configuration()
        configuration.readonly = true
        let queue: DatabaseQueue
        do {
            queue = try DatabaseQueue(path: url.path, configuration: configuration)
        } catch {
            throw BackupRestoreError.invalidFile("The file is not a readable database.")
        }
        do {
            try queue.read { db in
                let tableNames = try String.fetchAll(
                    db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
                )
                let missing = expectedTables.filter { !tableNames.contains($0) }
                guard missing.isEmpty else {
                    throw BackupRestoreError.invalidFile(
                        "The file is not a PaashERP database (missing \(missing.joined(separator: ", ")))."
                    )
                }
                let schemaVersions = Set(
                    try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
                )
                let newer = schemaVersions.subtracting(supportedSchemaVersions)
                guard newer.isEmpty else {
                    throw BackupRestoreError.invalidFile(
                        "This backup was made by a newer version of PaashERP (schema \(newer.sorted().joined(separator: ", "))) and cannot be restored by this version."
                    )
                }
                guard !schemaVersions.isEmpty else {
                    throw BackupRestoreError.invalidFile(
                        "This backup has no recorded schema version, so it cannot be validated."
                    )
                }
                let checks = try String.fetchAll(db, sql: "PRAGMA quick_check")
                guard checks.allSatisfy({ $0 == "ok" }) else {
                    throw BackupRestoreError.invalidFile("The database failed its integrity check.")
                }
            }
        } catch let error as BackupRestoreError {
            throw error
        } catch {
            throw BackupRestoreError.invalidFile("The database could not be read.")
        }
    }

    /// Replaces the live database file with the backup, discarding any stale
    /// SQLite sidecar (`-wal`, `-shm`, `-journal`) files first.
    static func replace(databaseURL: URL, with backupURL: URL) throws {
        guard databaseURL.standardizedFileURL.path != backupURL.standardizedFileURL.path else {
            throw BackupRestoreError.invalidFile("That is the live database itself — pick a different backup file.")
        }
        let fileManager = FileManager.default
        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecar = URL(fileURLWithPath: databaseURL.path + suffix)
            if fileManager.fileExists(atPath: sidecar.path) {
                try? fileManager.removeItem(at: sidecar)
            }
        }
        do {
            let data = try Data(contentsOf: backupURL)
            try data.write(to: databaseURL, options: .atomic)
        } catch {
            throw BackupRestoreError.replaceFailed("The backup could not be written in place of the live database.")
        }
    }
}

enum BackupRestoreError: LocalizedError {
    case invalidFile(String)
    case replaceFailed(String)
    case backupFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFile(let message), .replaceFailed(let message), .backupFailed(let message): message
        }
    }
}