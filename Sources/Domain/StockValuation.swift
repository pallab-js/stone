import Foundation

/// Purely integer stock valuation: `qtyKg` × `ratePaisePerTonne` / 1000,
/// rounded to the nearest paisa. Used by the dashboard and the stock screen so
/// "stock value" is one number everywhere, with no Double round-trip drift.
enum StockValuation {
    static func value(ratePaisePerTonne: Int64, qtyKg: Int64) -> Int64 {
        (ratePaisePerTonne * qtyKg + 500) / 1000
    }
}