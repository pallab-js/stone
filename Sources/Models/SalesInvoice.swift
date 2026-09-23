import Foundation
import GRDB

struct SalesInvoice: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: Int64?
    var invoiceNo: String
    var date: Date
    var customerId: Int64
    var vehicleId: Int64?
    var placeOfSupply: String?
    var state: String?
    var status: Status
    var subtotalPaise: Int64
    var cgstPaise: Int64
    var sgstPaise: Int64
    var igstPaise: Int64
    var transportChargePaise: Int64
    var discountPaise: Int64
    var grandTotalPaise: Int64
    var remarks: String?
    var createdAt: Date
    var updatedAt: Date

    enum Status: String, Codable, Sendable, CaseIterable, Identifiable {
        case drafted = "drafted"
        case dispatched = "dispatched"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .drafted: "Draft"
            case .dispatched: "Dispatched"
            }
        }
    }

    init(
        id: Int64? = nil,
        invoiceNo: String,
        date: Date,
        customerId: Int64,
        vehicleId: Int64? = nil,
        placeOfSupply: String? = nil,
        state: String? = nil,
        status: Status = .dispatched,
        subtotalPaise: Int64 = 0,
        cgstPaise: Int64 = 0,
        sgstPaise: Int64 = 0,
        igstPaise: Int64 = 0,
        transportChargePaise: Int64 = 0,
        discountPaise: Int64 = 0,
        grandTotalPaise: Int64 = 0,
        remarks: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.invoiceNo = invoiceNo
        self.date = date
        self.customerId = customerId
        self.vehicleId = vehicleId
        self.placeOfSupply = placeOfSupply
        self.state = state
        self.status = status
        self.subtotalPaise = subtotalPaise
        self.cgstPaise = cgstPaise
        self.sgstPaise = sgstPaise
        self.igstPaise = igstPaise
        self.transportChargePaise = transportChargePaise
        self.discountPaise = discountPaise
        self.grandTotalPaise = grandTotalPaise
        self.remarks = remarks
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension SalesInvoice: TableRecord, FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "salesInvoices" }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    static let items = hasMany(InvoiceItem.self)
    static let dispatch = hasOne(DispatchDetail.self)

    var items: QueryInterfaceRequest<InvoiceItem> { request(for: Self.items) }
    var dispatch: QueryInterfaceRequest<DispatchDetail> { request(for: Self.dispatch) }
}

struct InvoiceItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: Int64?
    var invoiceId: Int64
    var productId: Int64
    var qtyKg: Int64
    var ratePaisePerTonne: Int64
    var amountPaise: Int64
    var gstRateBps: Int
    var hsn: String

    init(
        id: Int64? = nil,
        invoiceId: Int64,
        productId: Int64,
        qtyKg: Int64,
        ratePaisePerTonne: Int64,
        amountPaise: Int64,
        gstRateBps: Int,
        hsn: String
    ) {
        self.id = id
        self.invoiceId = invoiceId
        self.productId = productId
        self.qtyKg = qtyKg
        self.ratePaisePerTonne = ratePaisePerTonne
        self.amountPaise = amountPaise
        self.gstRateBps = gstRateBps
        self.hsn = hsn
    }
}

extension InvoiceItem: TableRecord, FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "invoiceItems" }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct DispatchDetail: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: Int64?
    var invoiceId: Int64
    var tareKg: Int64?
    var grossKg: Int64?
    var netKg: Int64?
    var loadedBy: String?
    var timeOut: Date?
    var backNote: String?

    init(
        id: Int64? = nil,
        invoiceId: Int64,
        tareKg: Int64? = nil,
        grossKg: Int64? = nil,
        netKg: Int64? = nil,
        loadedBy: String? = nil,
        timeOut: Date? = nil,
        backNote: String? = nil
    ) {
        self.id = id
        self.invoiceId = invoiceId
        self.tareKg = tareKg
        self.grossKg = grossKg
        self.netKg = netKg
        self.loadedBy = loadedBy
        self.timeOut = timeOut
        self.backNote = backNote
    }
}

extension DispatchDetail: TableRecord, FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "dispatchDetails" }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}