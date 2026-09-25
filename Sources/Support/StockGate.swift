import Foundation
import GRDB

enum InvoiceValidationError: LocalizedError, Equatable {
    case insufficientStock(product: String, availableKg: Int64, neededKg: Int64)

    var errorDescription: String? {
        switch self {
        case .insufficientStock(let product, let availableKg, let neededKg):
            "Not enough stock for \(product) — \(Format.tonnes(availableKg)) available, "
                + "\(Format.tonnes(neededKg)) required."
        }
    }
}

/// Pre-save validation that keeps the stock ledger non-negative.
///
/// Selling, wasting or reversing more than what is currently on hand would
/// produce negative stock, which corrupts the stock report and dashboard.
enum StockGate {
    /// Guards a debit that removes `removingKg` of *positive* stock from the
    /// ledger: can the balance absorb it without going negative? Used for
    /// wastage/adjustment-out movements, manual movement deletion, and any
    /// reversal of production output (deleting a batch, or shrinking one).
    /// `removingKg <= 0` never blocks. Throws
    /// `InvoiceValidationError.insufficientStock` on the first shortfall.
    static func requireForRemoval(
        db: Database,
        removingKg: Int64,
        productID: Int64,
        productName: (Int64) -> String?
    ) throws {
        guard removingKg > 0 else { return }
        let balance = try Int64.fetchOne(
            db,
            sql: "SELECT COALESCE(SUM(qtyKg), 0) FROM stockMovements WHERE productId = ?",
            arguments: [productID]
        ) ?? 0
        guard balance >= removingKg else {
            throw InvoiceValidationError.insufficientStock(
                product: productName(productID) ?? "Product",
                availableKg: balance,
                neededKg: removingKg
            )
        }
    }

    /// `required` maps productID → tonnes*kg needed by the about-to-be-saved invoice.
    /// Throws `InvoiceValidationError.insufficientStock` on the first shortfall.
    static func requireAvailable(
        db: Database,
        replacingInvoiceID: Int64?,
        required: [Int64: Int64],
        productName: (Int64) -> String?
    ) throws {
        for (productID, needed) in required where needed > 0 {
            let balance = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(qtyKg), 0) FROM stockMovements WHERE productId = ?",
                arguments: [productID]
            ) ?? 0
            let alreadySoldForInvoice = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(-qtyKg), 0) FROM stockMovements WHERE productId = ? AND type = ? AND refId = ?",
                arguments: [productID, StockMovement.MoveType.sale.rawValue, replacingInvoiceID ?? 0]
            ) ?? 0
            let available = balance + alreadySoldForInvoice
            guard available >= needed else {
                throw InvoiceValidationError.insufficientStock(
                    product: productName(productID) ?? "Product",
                    availableKg: available,
                    neededKg: needed
                )
            }
        }
    }

    /// Removes several quantities in one check.
    ///
    /// Quantities for the same product are summed first: calling the
    /// single-quantity gate once per line only proves the balance covers each
    /// line *individually*, so two 6 t lines of one product could both pass
    /// against an 8 t balance and still drive the ledger to −4 t. Entries with
    /// `qtyKg <= 0` are ignored. Throws on the first shortfall, in ascending
    /// product-id order so the reported error is deterministic.
    static func requireForRemoval(
        db: Database,
        removing pairs: [(productID: Int64, qtyKg: Int64)],
        productName: (Int64) -> String?
    ) throws {
        var totals: [Int64: Int64] = [:]
        for pair in pairs where pair.qtyKg > 0 {
            totals[pair.productID, default: 0] += pair.qtyKg
        }
        for productID in totals.keys.sorted() {
            try requireForRemoval(
                db: db,
                removingKg: totals[productID] ?? 0,
                productID: productID,
                productName: productName
            )
        }
    }

    /// Gate for editing a batch: for every product, the amount by which the
    /// stored (`old`) lines exceed the new ones is removed from the ledger, so
    /// it is that *total* per product that must fit the balance — comparing
    /// each old line against the new total separately misses the removal
    /// entirely when a batch holds several lines for the same product.
    static func requireForRemoval(
        db: Database,
        reducing oldPairs: [(productID: Int64, qtyKg: Int64)],
        to newByProduct: [Int64: Int64],
        productName: (Int64) -> String?
    ) throws {
        var oldTotals: [Int64: Int64] = [:]
        for pair in oldPairs where pair.qtyKg > 0 {
            oldTotals[pair.productID, default: 0] += pair.qtyKg
        }
        let removed = oldTotals.map { (productID: $0.key, qtyKg: $0.value - (newByProduct[$0.key] ?? 0)) }
        try requireForRemoval(db: db, removing: removed, productName: productName)
    }
}