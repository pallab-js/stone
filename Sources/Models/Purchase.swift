import Foundation
import GRDB

struct Purchase: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: Int64?
    var date: Date
    var supplierId: Int64?
    var category: Category
    var amountPaise: Int64
    var gstRateBps: Int
    var mode: Payment.Mode
    var qtyLitres: Double?
    var ratePaise: Int64?
    var notes: String?
    var createdAt: Date

    enum Category: String, Codable, Sendable, CaseIterable, Identifiable {
        case diesel = "diesel"
        case electricity = "electricity"
        case royalty = "royalty"
        case parts = "parts"
        case labour = "labour"
        case rent = "rent"
        case misc = "misc"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .diesel: "Diesel"
            case .electricity: "Electricity"
            case .royalty: "Quarry Royalty"
            case .parts: "Spare Parts"
            case .labour: "Labour"
            case .rent: "Rent"
            case .misc: "Miscellaneous"
            }
        }
    }

    init(
        id: Int64? = nil,
        date: Date = .now,
        supplierId: Int64? = nil,
        category: Category,
        amountPaise: Int64,
        gstRateBps: Int = 0,
        mode: Payment.Mode = .cash,
        qtyLitres: Double? = nil,
        ratePaise: Int64? = nil,
        notes: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.supplierId = supplierId
        self.category = category
        self.amountPaise = amountPaise
        self.gstRateBps = gstRateBps
        self.mode = mode
        self.qtyLitres = qtyLitres
        self.ratePaise = ratePaise
        self.notes = notes
        self.createdAt = createdAt
    }
}

extension Purchase: TableRecord, FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "purchases" }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}