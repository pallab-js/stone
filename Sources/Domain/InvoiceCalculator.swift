import Foundation

/// Single, testable source of truth for GST line and invoice totals.
///
/// All money is stored as paise (`Int64`) and quantities as kilograms
/// (`Int64`). Rates are per tonne in paise, so a line amount is
/// `qtyKg * ratePaisePerTonne / 1000`.
enum InvoiceCalculator {

    /// A single invoice line (product-level inputs only).
    struct Line: Equatable {
        var qtyKg: Int64
        var ratePaisePerTonne: Int64
        var gstRateBps: Int
    }

    /// Invoice-level totals.
    struct Totals: Equatable {
        var subtotalPaise: Int64
        var cgstPaise: Int64
        var sgstPaise: Int64
        var igstPaise: Int64
        var grandTotalPaise: Int64
    }

    /// A mismatch between the weighbridge's net weight and the quantity on the
    /// invoice's line items.
    struct DispatchWeightDiscrepancy: Equatable {
        var billedKg: Int64
        var weighedKg: Int64
    }

    /// Flags when the weighbridge net weight disagrees with the sum of billed
    /// line quantities. Returns nil when there is no weighbridge reading or the
    /// two agree within `toleranceKg` (default 100 kg ≈ 0.1 t). A tolerance is
    /// used so that a few kilograms of rounding never produces a warning, while
    /// a genuinely different dispatch still does.
    static func dispatchDiscrepancy(
        weighbridgeNetKg: Int64?,
        lineTotalKg: Int64,
        toleranceKg: Int64 = 100
    ) -> DispatchWeightDiscrepancy? {
        guard let weighed = weighbridgeNetKg else { return nil }
        let diff = weighed > lineTotalKg ? weighed - lineTotalKg : lineTotalKg - weighed
        guard diff > toleranceKg else { return nil }
        return DispatchWeightDiscrepancy(billedKg: lineTotalKg, weighedKg: weighed)
    }

    /// True when adding an invoice's total to the customer's current outstanding
    /// pushes their exposure over the credit limit. Passing
    /// `existingInvoiceTotalPaise` lets editing a saved invoice *replace* its
    /// total instead of double-counting it. A credit limit of 0 means
    /// "no limit" and never warns.
    static func exceedsCreditLimit(
        creditLimitPaise: Int64,
        currentOutstandingPaise: Int64,
        newInvoiceTotalPaise: Int64,
        existingInvoiceTotalPaise: Int64 = 0
    ) -> Bool {
        guard creditLimitPaise > 0 else { return false }
        let projectedOutstanding = currentOutstandingPaise - existingInvoiceTotalPaise + newInvoiceTotalPaise
        return projectedOutstanding > creditLimitPaise
    }

    /// Taxable amount for one line:
    /// `qtyKg * ratePaisePerTonne / 1000` (rate is per tonne in paise).
    static func amountPaise(qtyKg: Int64, ratePaisePerTonne: Int64) -> Int64 {
        qtyKg * ratePaisePerTonne / 1000
    }

    /// GST amount for one line given its taxable amount and rate in basis
    /// points (e.g. 500 = 5%).
    static func gstPaise(amountPaise: Int64, bps: Int) -> Int64 {
        amountPaise * Int64(bps) / 10_000
    }

    /// Aggregate totals across all lines. For intra-state sales the combined
    /// GST is split as CGST/SGST (split in half, remainder to SGST); for
    /// inter-state sales the full GST is IGST. `amountPaise` is only used to
    /// recompute each line's GST so a single `Line` is enough.
    static func totals(
        lines: [Line],
        transportPaise: Int64 = 0,
        discountPaise: Int64 = 0,
        isIntraState: Bool
    ) -> Totals {
        var subtotal: Int64 = 0
        var cgst: Int64 = 0
        var sgst: Int64 = 0
        var igst: Int64 = 0
        for line in lines {
            let amount = amountPaise(qtyKg: line.qtyKg, ratePaisePerTonne: line.ratePaisePerTonne)
            subtotal += amount
            let gst = gstPaise(amountPaise: amount, bps: line.gstRateBps)
            if isIntraState {
                cgst += gst / 2
                sgst += gst - gst / 2
            } else {
                igst += gst
            }
        }
        let grand = max(0, subtotal + cgst + sgst + igst + transportPaise - discountPaise)
        return Totals(
            subtotalPaise: subtotal,
            cgstPaise: cgst,
            sgstPaise: sgst,
            igstPaise: igst,
            grandTotalPaise: grand
        )
    }

    /// How GST is composed on a tax invoice.
    enum SplitMode: Equatable {
        /// CGST + SGST, charged on sales within the same state.
        case intraState
        /// Single IGST, charged on inter-state sales.
        case interState
    }

    /// The split implied by an invoice's *already-recorded* taxes. Used when
    /// editing a saved invoice so the CGST/SGST vs IGST structure it was
    /// originally dispatched under stays stable even if the customer's
    /// registered state has since changed in Masters. Returns nil when the
    /// recorded taxes don't determine one (fresh drafts, zero-GST invoices).
    static func recordedSplitMode(cgstPaise: Int64, sgstPaise: Int64, igstPaise: Int64) -> SplitMode? {
        if igstPaise > 0 { return .interState }
        if cgstPaise > 0 || sgstPaise > 0 { return .intraState }
        return nil
    }

    /// Whether selling to `customerState` from `businessState` is intra-state.
    /// A missing customer state or business state conservatively defaults to
    /// intra-state (CGST/SGST), matching the GST treatment when the place of
    /// supply can't be determined.
    static func isIntraState(customerState: String?, businessState: String) -> Bool {
        let business = businessState.trimmingCharacters(in: .whitespaces)
        if business.isEmpty { return true }
        let customer = customerState?.trimmingCharacters(in: .whitespaces)
        guard let customer, !customer.isEmpty else { return true }
        return customer == business
    }
}
