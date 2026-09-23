import Foundation
import GRDB

struct StockMovement: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: Int64?
    var productId: Int64
    var date: Date
    var type: MoveType
    var qtyKg: Int64
    var refId: Int64?
    var remarks: String?
    var createdAt: Date

    enum MoveType: String, Codable, Sendable, CaseIterable, Identifiable {
        case opening = "opening"
        case production = "production"
        case sale = "sale"
        case wastage = "wastage"
        case adjustmentIn = "adjustmentIn"
        case adjustmentOut = "adjustmentOut"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .opening: "Opening"
            case .production: "Production"
            case .sale: "Sale"
            case .wastage: "Wastage"
            case .adjustmentIn: "Adjustment In"
            case .adjustmentOut: "Adjustment Out"
            }
        }
    }

    init(
        id: Int64? = nil,
        productId: Int64,
        date: Date,
        type: MoveType,
        qtyKg: Int64,
        refId: Int64? = nil,
        remarks: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.productId = productId
        self.date = date
        self.type = type
        self.qtyKg = qtyKg
        self.refId = refId
        self.remarks = remarks
        self.createdAt = createdAt
    }
}

extension StockMovement: TableRecord, FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "stockMovements" }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}