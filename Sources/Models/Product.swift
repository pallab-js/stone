import Foundation
import GRDB

struct Product: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: Int64?
    var code: String
    var name: String
    var category: String
    var unit: String
    var cftFactor: Double?
    var hsn: String
    var gstRateBps: Int
    var sortOrder: Int
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: Int64? = nil,
        code: String,
        name: String,
        category: String = "aggregate",
        unit: String = "tonne",
        cftFactor: Double? = nil,
        hsn: String = "2517",
        gstRateBps: Int = 500,
        sortOrder: Int = 0,
        isActive: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.code = code
        self.name = name
        self.category = category
        self.unit = unit
        self.cftFactor = cftFactor
        self.hsn = hsn
        self.gstRateBps = gstRateBps
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Product: TableRecord, FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "products" }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct ProductRate: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: Int64?
    var productId: Int64
    var effectiveDate: Date
    var ratePaisePerTonne: Int64

    init(id: Int64? = nil, productId: Int64, effectiveDate: Date = .now, ratePaisePerTonne: Int64) {
        self.id = id
        self.productId = productId
        self.effectiveDate = effectiveDate
        self.ratePaisePerTonne = ratePaisePerTonne
    }
}

extension ProductRate: TableRecord, FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "productRates" }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}