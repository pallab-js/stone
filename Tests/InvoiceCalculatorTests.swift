import XCTest
@testable import PaashERP

final class InvoiceCalculatorTests: XCTestCase {

    // amount = qtyKg × ratePaisePerTonne ÷ 1000
    func testLineAmount() {
        XCTAssertEqual(InvoiceCalculator.amountPaise(qtyKg: 10_000, ratePaisePerTonne: 120_000), 1_200_000)
        XCTAssertEqual(InvoiceCalculator.amountPaise(qtyKg: 3_333, ratePaisePerTonne: 95_000), 316_635)
    }

    // gst = amount × bps ÷ 10_000
    func testLineGST() {
        XCTAssertEqual(InvoiceCalculator.gstPaise(amountPaise: 1_200_000, bps: 500), 60_000)
        XCTAssertEqual(InvoiceCalculator.gstPaise(amountPaise: 316_635, bps: 500), 15_831)
        XCTAssertEqual(InvoiceCalculator.gstPaise(amountPaise: 269_500, bps: 1800), 48_510)
    }

    func testIntraStateSplitsGSTEqually() {
        let totals = InvoiceCalculator.totals(
            lines: [InvoiceCalculator.Line(qtyKg: 10_000, ratePaisePerTonne: 120_000, gstRateBps: 500)],
            transportPaise: 50_000,
            isIntraState: true
        )
        XCTAssertEqual(totals.subtotalPaise, 1_200_000)
        XCTAssertEqual(totals.cgstPaise, 30_000)
        XCTAssertEqual(totals.sgstPaise, 30_000)
        XCTAssertEqual(totals.igstPaise, 0)
        XCTAssertEqual(totals.grandTotalPaise, 1_310_000)
    }

    // Odd paise: CGST floors, the remainder goes to SGST so the split never loses paise.
    func testOddPaiseGSTRoundRobin() {
        let totals = InvoiceCalculator.totals(
            lines: [
                InvoiceCalculator.Line(qtyKg: 3_333, ratePaisePerTonne: 95_000, gstRateBps: 500),
                InvoiceCalculator.Line(qtyKg: 2_450, ratePaisePerTonne: 110_000, gstRateBps: 1800)
            ],
            isIntraState: true
        )
        XCTAssertEqual(totals.subtotalPaise, 316_635 + 269_500)
        XCTAssertEqual(totals.cgstPaise, 7_915 + 24_255)
        XCTAssertEqual(totals.sgstPaise, 7_916 + 24_255)
        XCTAssertEqual(totals.cgstPaise + totals.sgstPaise, 15_831 + 48_510)
    }

    func testInterStateUsesIGSTOnly() {
        let totals = InvoiceCalculator.totals(
            lines: [InvoiceCalculator.Line(qtyKg: 20_000, ratePaisePerTonne: 125_000, gstRateBps: 500)],
            isIntraState: false
        )
        XCTAssertEqual(totals.subtotalPaise, 2_500_000)
        XCTAssertEqual(totals.cgstPaise, 0)
        XCTAssertEqual(totals.sgstPaise, 0)
        XCTAssertEqual(totals.igstPaise, 125_000)
        XCTAssertEqual(totals.grandTotalPaise, 2_625_000)
    }

    // MARK: Recorded split (tax structure immutability when editing)

    func testRecordedSplitModeInfersIntraStateFromCGSTOrSGST() {
        XCTAssertEqual(InvoiceCalculator.recordedSplitMode(cgstPaise: 100, sgstPaise: 100, igstPaise: 0), .intraState)
        XCTAssertEqual(InvoiceCalculator.recordedSplitMode(cgstPaise: 100, sgstPaise: 0, igstPaise: 0), .intraState)
        XCTAssertEqual(InvoiceCalculator.recordedSplitMode(cgstPaise: 0, sgstPaise: 100, igstPaise: 0), .intraState)
    }

    func testRecordedSplitModeInfersInterStateFromIGST() {
        XCTAssertEqual(InvoiceCalculator.recordedSplitMode(cgstPaise: 0, sgstPaise: 0, igstPaise: 100), .interState)
    }

    func testRecordedSplitModeIsNilWhenIndeterminate() {
        XCTAssertNil(InvoiceCalculator.recordedSplitMode(cgstPaise: 0, sgstPaise: 0, igstPaise: 0))
    }

    func testRecordedSplitModePrefersIGSTWhenTaxesConflict() {
        // IGST wins so an inter-state invoice never silently reverts to
        // CGST/SGST merely because a customer now shares the business state.
        XCTAssertEqual(InvoiceCalculator.recordedSplitMode(cgstPaise: 100, sgstPaise: 100, igstPaise: 500), .interState)
    }

    // MARK: Intra/inter-state derivation from customer vs business state

    func testIsIntraStateMatchesWhenStatesAgree() {
        XCTAssertTrue(InvoiceCalculator.isIntraState(customerState: "Maharashtra", businessState: "Maharashtra"))
        XCTAssertTrue(InvoiceCalculator.isIntraState(customerState: "  Maharashtra ", businessState: "Maharashtra"))
    }

    func testIsIntraStateIsFalseWhenStatesDiffer() {
        XCTAssertFalse(InvoiceCalculator.isIntraState(customerState: "Karnataka", businessState: "Maharashtra"))
    }

    func testIsIntraStateDefaultsToTrueWhenStateMissing() {
        XCTAssertTrue(InvoiceCalculator.isIntraState(customerState: nil, businessState: "Maharashtra"))
        XCTAssertTrue(InvoiceCalculator.isIntraState(customerState: "   ", businessState: "Maharashtra"))
        XCTAssertTrue(InvoiceCalculator.isIntraState(customerState: "Maharashtra", businessState: ""))
        XCTAssertTrue(InvoiceCalculator.isIntraState(customerState: nil, businessState: ""))
    }

    func testDiscountAppliesButGrandTotalNeverGoesNegative() {
        let lines = [InvoiceCalculator.Line(qtyKg: 1_000, ratePaisePerTonne: 100_000, gstRateBps: 500)]
        let withDiscount = InvoiceCalculator.totals(
            lines: lines, discountPaise: 10_000, isIntraState: true
        )
        XCTAssertEqual(withDiscount.grandTotalPaise, 95_000)
        let overDiscounted = InvoiceCalculator.totals(
            lines: lines, discountPaise: 500_000, isIntraState: true
        )
        XCTAssertEqual(overDiscounted.grandTotalPaise, 0)
    }

    // MARK: Dispatch weight vs billed quantity

    func testDispatchDiscrepancyIsNilWithoutWeighbridge() {
        XCTAssertNil(InvoiceCalculator.dispatchDiscrepancy(weighbridgeNetKg: nil, lineTotalKg: 12_345))
        XCTAssertNil(InvoiceCalculator.dispatchDiscrepancy(weighbridgeNetKg: nil, lineTotalKg: 0))
    }

    func testDispatchDiscrepancyIsNilWhenWeightsAgree() {
        XCTAssertNil(InvoiceCalculator.dispatchDiscrepancy(weighbridgeNetKg: 12_345, lineTotalKg: 12_345))
        XCTAssertNil(InvoiceCalculator.dispatchDiscrepancy(weighbridgeNetKg: 12_345, lineTotalKg: 12_245))
        XCTAssertNil(InvoiceCalculator.dispatchDiscrepancy(weighbridgeNetKg: 12_345, lineTotalKg: 12_445))
    }

    func testDispatchDiscrepancyReportedOnlyBeyondTolerance() {
        XCTAssertNotNil(InvoiceCalculator.dispatchDiscrepancy(weighbridgeNetKg: 12_345, lineTotalKg: 12_845))
        XCTAssertNotNil(InvoiceCalculator.dispatchDiscrepancy(weighbridgeNetKg: 13_000, lineTotalKg: 12_345))
        XCTAssertNil(InvoiceCalculator.dispatchDiscrepancy(
            weighbridgeNetKg: 12_045,
            lineTotalKg: 12_345,
            toleranceKg: 1_000
        ))
        XCTAssertNotNil(InvoiceCalculator.dispatchDiscrepancy(
            weighbridgeNetKg: 12_045,
            lineTotalKg: 12_345,
            toleranceKg: 99
        ))
    }

    func testDispatchDiscrepancySurfacesWeighbridgeWithNoLines() {
        let discrepancy = InvoiceCalculator.dispatchDiscrepancy(weighbridgeNetKg: 10_000, lineTotalKg: 0)
        XCTAssertEqual(discrepancy?.billedKg, 0)
        XCTAssertEqual(discrepancy?.weighedKg, 10_000)
    }

    // MARK: Credit limit

    func testCreditLimitIsIgnoredWhenUnset() {
        XCTAssertFalse(InvoiceCalculator.exceedsCreditLimit(
            creditLimitPaise: 0,
            currentOutstandingPaise: 10_000_000_00,
            newInvoiceTotalPaise: 5_000_00
        ))
    }

    func testCreditLimitNotExceededStaysWithin() {
        XCTAssertFalse(InvoiceCalculator.exceedsCreditLimit(
            creditLimitPaise: 150_000_00,
            currentOutstandingPaise: 100_000_00,
            newInvoiceTotalPaise: 50_000_00
        ))
        XCTAssertFalse(InvoiceCalculator.exceedsCreditLimit(
            creditLimitPaise: 150_000_00,
            currentOutstandingPaise: 100_000_00,
            newInvoiceTotalPaise: 50_000_00 - 100
        ))
    }

    func testCreditLimitExceeded() {
        XCTAssertTrue(InvoiceCalculator.exceedsCreditLimit(
            creditLimitPaise: 149_999_00,
            currentOutstandingPaise: 100_000_00,
            newInvoiceTotalPaise: 50_000_00
        ))
        XCTAssertTrue(InvoiceCalculator.exceedsCreditLimit(
            creditLimitPaise: 150_000_00,
            currentOutstandingPaise: 100_000_00,
            newInvoiceTotalPaise: 50_000_00 + 100
        ))
    }

    // Editing a saved invoice replaces its total rather than double-counting it.
    func testCreditLimitReplaceDoesNotDoubleCountExistingInvoice() {
        XCTAssertFalse(InvoiceCalculator.exceedsCreditLimit(
            creditLimitPaise: 100_000_00,
            currentOutstandingPaise: 100_000_00,
            newInvoiceTotalPaise: 40_000_00,
            existingInvoiceTotalPaise: 50_000_00
        ))
        XCTAssertTrue(InvoiceCalculator.exceedsCreditLimit(
            creditLimitPaise: 120_000_00,
            currentOutstandingPaise: 100_000_00,
            newInvoiceTotalPaise: 80_000_00,
            existingInvoiceTotalPaise: 50_000_00
        ))
    }

    // Shrinking an invoice while editing frees headroom: the exposure must be
    // recomputed as current − old + new, not held at its previous level.
    func testCreditLimitReductionFreesHeadroom() {
        XCTAssertFalse(InvoiceCalculator.exceedsCreditLimit(
            creditLimitPaise: 90_000_00,
            currentOutstandingPaise: 100_000_00,
            newInvoiceTotalPaise: 20_000_00,
            existingInvoiceTotalPaise: 50_000_00
        ))
        // …but it can never be counted twice if the caller omits the old total.
        XCTAssertTrue(InvoiceCalculator.exceedsCreditLimit(
            creditLimitPaise: 90_000_00,
            currentOutstandingPaise: 100_000_00,
            newInvoiceTotalPaise: 20_000_00
        ))
    }
}