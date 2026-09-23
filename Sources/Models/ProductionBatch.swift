import Foundation
import GRDB

struct ProductionBatch: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: Int64?
    var date: Date
    var shift: String
    var machineHours: Double?
    var dieselLitres: Double?
    var operatorName: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: Int64? = nil,
        date: Date,
        shift: String = "A",
        machineHours: Double? = nil,
        dieselLitres: Double? = nil,
        operatorName: String? = nil,
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.shift = shift
        self.machineHours = machineHours
        self.dieselLitres = dieselLitres
        self.operatorName = operatorName
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension ProductionBatch: TableRecord, FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "productionBatches" }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    static let items = hasMany(ProductionItem.self)

    var items: QueryInterfaceRequest<ProductionItem> {
        request(for: Self.items)
    }
}

struct ProductionItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: Int64?
    var batchId: Int64
    var productId: Int64
    var qtyKg: Int64

    init(id: Int64? = nil, batchId: Int64, productId: Int64, qtyKg: Int64) {
        self.id = id
        self.batchId = batchId
        self.productId = productId
        self.qtyKg = qtyKg
    }
}

extension ProductionItem: TableRecord, FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "productionItems" }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}