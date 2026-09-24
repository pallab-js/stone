import Foundation
import GRDB

/// Single, shared definition of "who owes what" so the dashboard, sales
/// editor, sales table, customers list and receivables-aging report all agree
/// on the same numbers.
///
/// Allocation policy (per customer):
/// 1. A payment linked to an invoice (`invoiceId` set) reduces only that
///    invoice.
/// 2. The opening balance and unlinked payments (advances, "General") settle
///    the oldest debts first — the opening balance, then invoices from oldest
///    to newest (FIFO), exactly like a running ledger.
/// 3. A customer's outstanding is always
///    `max(0, openingBalance + Σ invoice totals − Σ all payments)`, and every
///    surface (per-invoice due, aging buckets, customer lists) is derived from
///    that same allocation, so the numbers can never disagree.
///
/// Invoices are expected oldest-first; `snapshot` fetches them ordered by
/// date. Cancelled invoices are excluded from the receivable pool.
enum ReceivablesCalculator {

    /// A single open invoice and how much of it is still due after allocation.
    struct InvoiceDue: Equatable, Sendable {
        var invoiceId: Int64
        var invoiceNo: String
        var date: Date
        var grandTotalPaise: Int64
        var paidPaise: Int64
        var duePaise: Int64
    }

    /// A customer's full receivables picture.
    struct CustomerDue: Equatable, Sendable {
        var customerId: Int64
        var openingBalancePaise: Int64
        var openingDuePaise: Int64
        var invoices: [InvoiceDue]

        /// Outstanding including the carry-forward opening balance.
        var outstandingPaise: Int64 {
            openingDuePaise + invoices.reduce(0) { $0 + $1.duePaise }
        }
    }

    /// Everything the receivables screens need, computed in one pass.
    struct Summary: Equatable, Sendable {
        var byCustomer: [CustomerDue]

        var totalOutstandingPaise: Int64 {
            byCustomer.reduce(0) { $0 + $1.outstandingPaise }
        }

        /// Count of invoices on record (all, not just those still owing).
        var invoiceCount: Int {
            byCustomer.reduce(0) { $0 + $1.invoices.count }
        }
    }

    /// Full snapshot from the database.
    static func snapshot(db: Database) throws -> Summary {
        let customers = try Customer.order(Column("name")).fetchAll(db)
        let invoices = try SalesInvoice
            .filter(Column("status") != SalesInvoice.Status.cancelled.rawValue)
            .order(Column("date"), Column("id"))
            .fetchAll(db)
        struct PaymentRow: Decodable, FetchableRecord {
            var partyId: Int64
            var invoiceId: Int64?
            var amountPaise: Int64
        }
        let payments = try PaymentRow.fetchAll(
            db,
            sql: "SELECT partyId, invoiceId, amountPaise FROM payments WHERE partyType = ?",
            arguments: [Payment.PartyType.customer.rawValue]
        )

        var invoicesByCustomer: [Int64: [SalesInvoice]] = [:]
        for invoice in invoices {
            invoicesByCustomer[invoice.customerId, default: []].append(invoice)
        }
        var linkedByCustomer: [Int64: [Int64: Int64]] = [:]
        var unlinkedByCustomer: [Int64: Int64] = [:]
        for payment in payments {
            guard payment.amountPaise > 0 else { continue }
            if let invoiceID = payment.invoiceId {
                linkedByCustomer[payment.partyId, default: [:]][invoiceID, default: 0] += payment.amountPaise
            } else {
                unlinkedByCustomer[payment.partyId, default: 0] += payment.amountPaise
            }
        }

        let customersWithDues = customers.compactMap { customer -> CustomerDue? in
            guard let id = customer.id else { return nil }
            return dues(
                customerID: id,
                openingBalancePaise: customer.openingBalancePaise,
                invoices: invoicesByCustomer[id] ?? [],
                linkedPaid: linkedByCustomer[id] ?? [:],
                unlinkedPaid: unlinkedByCustomer[id] ?? 0
            )
        }
        return Summary(byCustomer: customersWithDues)
    }

    /// Core allocation. Pure and testable: given a customer's raw inputs
    /// (invoices oldest-first), returns per-invoice dues plus the
    /// opening-balance residual.
    static func dues(
        customerID: Int64,
        openingBalancePaise: Int64,
        invoices: [SalesInvoice],
        linkedPaid: [Int64: Int64],
        unlinkedPaid: Int64
    ) -> CustomerDue {
        struct Debt {
            var invoice: SalesInvoice?
            var amount: Int64
        }
        var debts: [Debt] = []
        if openingBalancePaise > 0 {
            debts.append(Debt(invoice: nil, amount: openingBalancePaise))
        }
        for invoice in invoices {
            let gross = max(0, invoice.grandTotalPaise - (linkedPaid[invoice.id ?? 0] ?? 0))
            debts.append(Debt(invoice: invoice, amount: gross))
        }
        // A negative opening balance is carried-forward credit and settles the
        // oldest debts first, exactly as an unlinked payment would.
        let pool = unlinkedPaid + max(0, -openingBalancePaise)
        var remaining = pool
        for index in debts.indices where remaining > 0 && debts[index].amount > 0 {
            let applied = min(remaining, debts[index].amount)
            debts[index].amount -= applied
            remaining -= applied
        }
        // Leftover pool is credit on account and simply zeroes outstanding.

        var invoiceDues: [InvoiceDue] = []
        var openingDue: Int64 = 0
        for debt in debts {
            guard let invoice = debt.invoice else {
                openingDue = debt.amount
                continue
            }
            invoiceDues.append(InvoiceDue(
                invoiceId: invoice.id ?? 0,
                invoiceNo: invoice.invoiceNo,
                date: invoice.date,
                grandTotalPaise: invoice.grandTotalPaise,
                paidPaise: invoice.grandTotalPaise - debt.amount,
                duePaise: debt.amount
            ))
        }
        return CustomerDue(
            customerId: customerID,
            openingBalancePaise: openingBalancePaise,
            openingDuePaise: openingDue,
            invoices: invoiceDues
        )
    }
}