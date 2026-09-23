import Foundation
import GRDB

enum InvoiceValidationError: LocalizedError, Equatable {
    case insufficientStock(product: String, availableKg: Int64, neededKg: Int64)

    var errorDescription: String? {
        switch self {
        case .insufficientStock(let product, let availableKg, let neededKg):
            "Not enough stock for \(product) — \(Format.tonnes(availableKg)) available, "
                + "this invoice needs \(Format.tonnes(neededKg))."
        }
    }
}

/// Pre-save validation for the Sales editor.
///
/// Selling more than what is currently in the ledger would produce negative
/// stock, which corrupts the stock report and dashboard. The gate re-adds the
/// stock already consumed by the invoice being edited (its sale movements are
/// replaced on save, not accumulated), so editing an invoice is always allowed
/// as long as the net change keeps every product's balance non-negative.
enum StockGate {
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
}