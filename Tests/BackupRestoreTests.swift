import XCTest
import GRDB
@testable import PaashERP

final class BackupRestoreTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUp() {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupRestoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func fileURL(_ name: String) -> URL {
        tempDirectory.appendingPathComponent(name)
    }

    private func makeDatabase(at url: URL, businessName: String) throws -> AppDatabase {
        let db = try AppDatabase.open(at: url)
        try db.dbQueue.write { database in
            try AppSetting.set(key: "business_name", value: businessName, db: database)
        }
        return db
    }

    func testValidateAcceptsARealPaashERPDatabase() throws {
        let dbURL = fileURL("live.sqlite")
        _ = try makeDatabase(at: dbURL, businessName: "Current")
        try BackupRestore.validateBackup(at: dbURL)
    }

    func testValidateRejectsNonDatabaseFile() throws {
        let garbageURL = fileURL("garbage.sqlite")
        try Data("not a sqlite file at all".utf8).write(to: garbageURL)
        XCTAssertThrowsError(try BackupRestore.validateBackup(at: garbageURL))
    }

    func testValidateRejectsFileMissingExpectedTables() throws {
        let partialURL = fileURL("partial.sqlite")
        var configuration = Configuration()
        configuration.label = "test.partial"
        let queue = try DatabaseQueue(path: partialURL.path, configuration: configuration)
        try queue.write { database in
            try database.execute(sql: "CREATE TABLE products (id INTEGER PRIMARY KEY)")
        }
        XCTAssertThrowsError(try BackupRestore.validateBackup(at: partialURL))
    }

    @MainActor
    func testRestoreSwapsLiveDatabaseWithBackup() throws {
        let liveURL = fileURL("live.sqlite")
        let backupURL = fileURL("backup.sqlite")
        _ = try makeDatabase(at: liveURL, businessName: "Old data")
        _ = try makeDatabase(at: backupURL, businessName: "Restored data")

        let state = try AppState(database: AppDatabase.open(at: liveURL), databaseURL: liveURL)
        let epochBefore = state.dataEpoch

        try state.restoreBackup(from: backupURL)

        let businessName = try state.database.dbQueue.read { database in
            try AppSetting.value(forKey: "business_name", db: database)
        }
        XCTAssertEqual(businessName, "Restored data")
        XCTAssertEqual(state.dataEpoch, epochBefore + 1, "Restore must bump dataEpoch to refresh every screen")
    }

    @MainActor
    func testRestoreRejectsItsOwnLiveDatabase() throws {
        let liveURL = fileURL("live.sqlite")
        _ = try makeDatabase(at: liveURL, businessName: "Only data")
        let state = try AppState(database: AppDatabase.open(at: liveURL), databaseURL: liveURL)
        XCTAssertThrowsError(try state.restoreBackup(from: liveURL))
    }

    @MainActor
    func testCreateBackupProducesConsistentRestorableFile() throws {
        let liveURL = fileURL("live.sqlite")
        let live = try makeDatabase(at: liveURL, businessName: "Original data")
        try live.dbQueue.write { database in
            var customer = Customer(name: "Snapshot Customer")
            try customer.insert(database)
        }
        let backupURL = fileURL("snapshot.sqlite")
        try BackupRestore.createBackup(from: live.dbQueue, to: backupURL)

        // The produced file is a valid, current-schema PaashERP database.
        XCTAssertNoThrow(try BackupRestore.validateBackup(at: backupURL))

        // Restoring from it yields identical data.
        try live.dbQueue.close()
        let state = try AppState(database: AppDatabase.open(at: liveURL), databaseURL: liveURL)
        try state.restoreBackup(from: backupURL)
        let restored = try state.database.dbQueue.read { database in
            (
                try AppSetting.value(forKey: "business_name", db: database),
                try Customer.filter(Column("name") == "Snapshot Customer").fetchCount(database)
            )
        }
        XCTAssertEqual(restored.0, "Original data")
        XCTAssertEqual(restored.1, 1)
    }

    func testValidateRejectsNewerSchemaBackup() throws {
        let url = fileURL("future.sqlite")
        let db = try makeDatabase(at: url, businessName: "Future")
        try db.dbQueue.close()
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { database in
            try database.execute(sql: "UPDATE grdb_migrations SET identifier = 'v999' WHERE identifier = 'v1'")
        }
        XCTAssertThrowsError(try BackupRestore.validateBackup(at: url))
    }

    func testValidateRejectsBackupWithoutRecordedSchema() throws {
        let url = fileURL("schemaless.sqlite")
        let db = try makeDatabase(at: url, businessName: "Ancient")
        try db.dbQueue.close()
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { database in
            try database.execute(sql: "DROP TABLE grdb_migrations")
        }
        XCTAssertThrowsError(try BackupRestore.validateBackup(at: url))
    }
}