import Foundation
import GRDB

struct AppSetting: Codable, Equatable, Hashable, Sendable {
    var key: String
    var value: String

    init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

extension AppSetting: TableRecord, FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "appSettings" }
}

extension AppSetting {
    static func value(forKey key: String, db: Database) throws -> String? {
        try AppSetting.fetchOne(db, key: key)?.value
    }

    static func set(key: String, value: String, db: Database) throws {
        if try AppSetting.fetchOne(db, key: key) != nil {
            var setting = AppSetting(key: key, value: value)
            try setting.update(db)
        } else {
            var setting = AppSetting(key: key, value: value)
            try setting.insert(db)
        }
    }

    static func intValue(forKey key: String, db: Database) throws -> Int? {
        guard let raw = try value(forKey: key, db: db) else { return nil }
        return Int(raw)
    }
}