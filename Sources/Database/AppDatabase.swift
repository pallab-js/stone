import Foundation
import GRDB

struct AppDatabase: Sendable {
    let dbQueue: DatabaseQueue

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try AppDatabaseMigrator.v1(db)
        }
        return migrator
    }

    static func inMemory() -> AppDatabase {
        let queue = try! DatabaseQueue()
        try! migrator.migrate(queue)
        return AppDatabase(dbQueue: queue)
    }

    static func defaultDatabaseURL() throws -> URL {
        let fileManager = FileManager.default
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AppDatabaseError.directoryUnavailable
        }
        let directory = base.appendingPathComponent("PaashERP", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("PaashERP.sqlite")
    }

    static func open(at url: URL) throws -> AppDatabase {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.label = "com.paasherp.database"
        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        try migrator.migrate(queue)
        return AppDatabase(dbQueue: queue)
    }

    var reader: any DatabaseReader { dbQueue }
    func writer() -> any DatabaseWriter { dbQueue }
}

enum AppDatabaseError: Error {
    case directoryUnavailable
}