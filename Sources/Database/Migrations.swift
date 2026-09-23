import Foundation
import GRDB

enum AppDatabaseMigrator {
    static func v1(_ db: Database) throws {
        try db.create(table: "products") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("code", .text).notNull().unique()
            t.column("name", .text).notNull()
            t.column("category", .text).notNull().defaults(to: "aggregate")
            t.column("unit", .text).notNull().defaults(to: "tonne")
            t.column("cftFactor", .double)
            t.column("hsn", .text).notNull().defaults(to: "2517")
            t.column("gstRateBps", .integer).notNull().defaults(to: 500)
            t.column("sortOrder", .integer).notNull().defaults(to: 0)
            t.column("isActive", .boolean).notNull().defaults(to: true)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        try db.create(table: "productRates") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("productId", .integer).notNull().references("products", onDelete: .cascade)
            t.column("effectiveDate", .datetime).notNull()
            t.column("ratePaisePerTonne", .integer).notNull()
            t.uniqueKey(["productId", "effectiveDate"])
        }

        try db.create(table: "customers") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
            t.column("gstin", .text)
            t.column("phone", .text)
            t.column("address", .text)
            t.column("city", .text)
            t.column("state", .text)
            t.column("creditLimitPaise", .integer).notNull().defaults(to: 0)
            t.column("openingBalancePaise", .integer).notNull().defaults(to: 0)
            t.column("isActive", .boolean).notNull().defaults(to: true)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        try db.create(table: "suppliers") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
            t.column("gstin", .text)
            t.column("phone", .text)
            t.column("address", .text)
            t.column("city", .text)
            t.column("isActive", .boolean).notNull().defaults(to: true)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        try db.create(table: "vehicles") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("number", .text).notNull().unique()
            t.column("ownership", .text).notNull().defaults(to: "own")
            t.column("capacityKg", .integer).notNull().defaults(to: 20000)
            t.column("driverName", .text)
            t.column("driverPhone", .text)
            t.column("isActive", .boolean).notNull().defaults(to: true)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        try db.create(table: "productionBatches") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("date", .datetime).notNull()
            t.column("shift", .text).notNull().defaults(to: "A")
            t.column("machineHours", .double)
            t.column("dieselLitres", .double)
            t.column("operatorName", .text)
            t.column("notes", .text)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        try db.create(table: "productionItems") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("batchId", .integer).notNull().references("productionBatches", onDelete: .cascade)
            t.column("productId", .integer).notNull().references("products")
            t.column("qtyKg", .integer).notNull()
        }

        try db.create(table: "salesInvoices") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("invoiceNo", .text).notNull().unique()
            t.column("date", .datetime).notNull()
            t.column("customerId", .integer).notNull().references("customers")
            t.column("vehicleId", .integer).references("vehicles")
            t.column("placeOfSupply", .text)
            t.column("state", .text)
            t.column("status", .text).notNull().defaults(to: "dispatched")
            t.column("subtotalPaise", .integer).notNull().defaults(to: 0)
            t.column("cgstPaise", .integer).notNull().defaults(to: 0)
            t.column("sgstPaise", .integer).notNull().defaults(to: 0)
            t.column("igstPaise", .integer).notNull().defaults(to: 0)
            t.column("transportChargePaise", .integer).notNull().defaults(to: 0)
            t.column("discountPaise", .integer).notNull().defaults(to: 0)
            t.column("grandTotalPaise", .integer).notNull().defaults(to: 0)
            t.column("remarks", .text)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        try db.create(table: "invoiceItems") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("invoiceId", .integer).notNull().references("salesInvoices", onDelete: .cascade)
            t.column("productId", .integer).notNull().references("products")
            t.column("qtyKg", .integer).notNull()
            t.column("ratePaisePerTonne", .integer).notNull()
            t.column("amountPaise", .integer).notNull()
            t.column("gstRateBps", .integer).notNull()
            t.column("hsn", .text).notNull()
        }

        try db.create(table: "dispatchDetails") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("invoiceId", .integer).notNull().unique().references("salesInvoices", onDelete: .cascade)
            t.column("tareKg", .integer)
            t.column("grossKg", .integer)
            t.column("netKg", .integer)
            t.column("loadedBy", .text)
            t.column("timeOut", .datetime)
            t.column("backNote", .text)
        }

        try db.create(table: "payments") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("date", .datetime).notNull()
            t.column("partyType", .text).notNull()
            t.column("partyId", .integer).notNull()
            t.column("kind", .text).notNull().defaults(to: "againstInvoice")
            t.column("invoiceId", .integer).references("salesInvoices", onDelete: .setNull)
            t.column("amountPaise", .integer).notNull()
            t.column("mode", .text).notNull().defaults(to: "cash")
            t.column("refNo", .text)
            t.column("notes", .text)
            t.column("createdAt", .datetime).notNull()
        }

        try db.create(table: "purchases") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("date", .datetime).notNull()
            t.column("supplierId", .integer).references("suppliers", onDelete: .setNull)
            t.column("category", .text).notNull().defaults(to: "misc")
            t.column("amountPaise", .integer).notNull()
            t.column("gstRateBps", .integer).notNull().defaults(to: 0)
            t.column("mode", .text).notNull().defaults(to: "cash")
            t.column("qtyLitres", .double)
            t.column("ratePaise", .integer)
            t.column("notes", .text)
            t.column("createdAt", .datetime).notNull()
        }

        try db.create(table: "stockMovements") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("productId", .integer).notNull().references("products")
            t.column("date", .datetime).notNull()
            t.column("type", .text).notNull()
            t.column("qtyKg", .integer).notNull()
            t.column("refId", .integer)
            t.column("remarks", .text)
            t.column("createdAt", .datetime).notNull()
        }

        try db.create(table: "appSettings") { t in
            t.primaryKey("key", .text)
            t.column("value", .text).notNull()
        }

        try db.create(index: "idxProductRatesProductId", on: "productRates", columns: ["productId"])
        try db.create(index: "idxProductionItemsBatchId", on: "productionItems", columns: ["batchId"])
        try db.create(index: "idxInvoiceItemsInvoiceId", on: "invoiceItems", columns: ["invoiceId"])
        try db.create(index: "idxSalesInvoicesDate", on: "salesInvoices", columns: ["date"])
        try db.create(index: "idxPaymentsParty", on: "payments", columns: ["partyType", "partyId"])
        try db.create(index: "idxStockMovementsProduct", on: "stockMovements", columns: ["productId", "date"])
    }
}