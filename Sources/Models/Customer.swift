import Foundation
import GRDB

struct Customer: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: Int64?
    var name: String
    var gstin: String?
    var phone: String?
    var address: String?
    var city: String?
    var state: String?
    var creditLimitPaise: Int64
    var openingBalancePaise: Int64
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
        state: String? = nil,
        creditLimitPaise: Int64 = 0,
        openingBalancePaise: Int64 = 0,
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
        self.state = state
        self.creditLimitPaise = creditLimitPaise
        self.openingBalancePaise = openingBalancePaise
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Customer: TableRecord, FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "customers" }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}