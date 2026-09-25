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
                // Matching table names alone do not prove a compatible schema:
                // a foreign SQLite file could pass and then fail on the first
                // query after it has already replaced the live database.
                let invoiceColumns = try String.fetchAll(
                    db, sql: "SELECT name FROM pragma_table_info('salesInvoices')"
                )
                guard invoiceColumns.contains("grandTotalPaise") else {
                    throw BackupRestoreError.invalidFile(
                        "The file has PaashERP table names but an incompatible schema."
                    )
                }
                guard try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty else {
                    throw BackupRestoreError.invalidFile("The database has broken record links.")
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

    /// Replaces the live database file with the backup.
    ///
    /// Ordering matters for safety: the backup bytes are read *before* anything
    /// is touched, `queue` is closed *before* the file it owns is swapped out
    /// (so no connection is ever left pointing at an unlinked inode), and stale
    /// SQLite sidecars (`-wal`, `-shm`, `-journal`) are removed only once the
    /// new content is ready to land — a leftover journal from the old database
    /// would otherwise be replayed over the restored file on the next open.
    static func replace(databaseURL: URL, with backupURL: URL, closing queue: DatabaseQueue) throws {
        guard databaseURL.resolvingSymlinksInPath().standardizedFileURL.path
            != backupURL.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw BackupRestoreError.invalidFile("That is the live database itself — pick a different backup file.")
        }
        let data: Data
        do {
            data = try Data(contentsOf: backupURL)
        } catch {
            throw BackupRestoreError.invalidFile("The backup file could not be read.")
        }
        try queue.close()
        let fileManager = FileManager.default
        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecar = URL(fileURLWithPath: databaseURL.path + suffix)
            guard fileManager.fileExists(atPath: sidecar.path) else { continue }
            do {
                try fileManager.removeItem(at: sidecar)
            } catch {
                throw BackupRestoreError.replaceFailed(
                    "A stale SQLite journal next to the live database could not be removed, so it was not overwritten."
                )
            }
        }
        do {
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