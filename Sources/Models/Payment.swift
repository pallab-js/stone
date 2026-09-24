import Foundation
import GRDB

struct Payment: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: Int64?
    var date: Date
    var partyType: PartyType
    var partyId: Int64
    var kind: Kind
    var invoiceId: Int64?
    var amountPaise: Int64
    var mode: Mode
    var refNo: String?
    var notes: String?
    var createdAt: Date

    enum PartyType: String, Codable, Sendable {
        case customer = "customer"
        case supplier = "supplier"
    }

    enum Kind: String, Codable, Sendable {
        case advance = "advance"
        case againstInvoice = "againstInvoice"
        case other = "other"

        var label: String {
            switch self {
            case .advance: "Advance"
            case .againstInvoice: "Against invoice"
            case .other: "Other"
            }
        }
    }

    enum Mode: String, Codable, Sendable, CaseIterable, Identifiable {
        case cash = "cash"
        case upi = "upi"
        case cheque = "cheque"
        case transfer = "transfer"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .cash: "Cash"
            case .upi: "UPI"
            case .cheque: "Cheque"
            case .transfer: "Bank Transfer"
            }
        }
    }

    init(
        id: Int64? = nil,
        date: Date = .now,
        partyType: PartyType,
        partyId: Int64,
        kind: Kind = .againstInvoice,
        invoiceId: Int64? = nil,
        amountPaise: Int64,
        mode: Mode = .cash,
        refNo: String? = nil,
        notes: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.partyType = partyType
        self.partyId = partyId
        self.kind = kind
        self.invoiceId = invoiceId
        self.amountPaise = amountPaise
        self.mode = mode
        self.refNo = refNo
        self.notes = notes
        self.createdAt = createdAt
    }
}

extension Payment: TableRecord, FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "payments" }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}