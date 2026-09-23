import Foundation
import GRDB

struct Supplier: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: Int64?
    var name: String
    var gstin: String?
    var phone: String?
    var address: String?
    var city: String?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: Int64? = nil,
        name: String,
        gstin: String? = nil,
        phone: String? = nil,
        address: String? = nil,
        city: String? = nil,
        isActive: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.gstin = gstin
        self.phone = phone
        self.address = address
        self.city = city
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Supplier: TableRecord, FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "suppliers" }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}