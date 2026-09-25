import SwiftUI
import AppKit
import GRDB

struct BusinessProfile: Equatable {
    var name: String
    var gstin: String?
    var address: String?
    var city: String?
    var state: String?
}

struct InvoiceDocumentLine: Identifiable, Equatable {
    var id: Int { index }
    var index: Int
    var productName: String
    var hsn: String
    var qtyKg: Int64
    var ratePaisePerTonne: Int64
    var gstRateBps: Int
    var amountPaise: Int64
}

struct InvoiceDocumentData: Equatable {
    var invoice: SalesInvoice
    var customerName: String
    var customerGstin: String?
    var customerAddress: String?
    var customerCity: String?
    var customerState: String?
    var customerPhone: String?
    var vehicleNumber: String?
    var items: [InvoiceDocumentLine]
    var dispatch: DispatchDetail?
    var business: BusinessProfile
}

struct InvoiceDocumentView: View {
    let data: InvoiceDocumentData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .padding(.vertical, 14)
            buyerBlock
            Divider()
                .padding(.vertical, 14)
            itemsBlock
            Divider()
                .padding(.vertical, 14)
            totalsBlock
            footer
        }
        .font(.system(size: 10))
        .padding(36)
        .frame(width: 595)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(data.business.name)
                    .font(.system(size: 15, weight: .bold))
                if let gstin = data.business.gstin, !gstin.isEmpty {
                    Text("GSTIN: \(gstin)")
                }
                if let address = data.business.address {
                    Text(address)
                }
                if let city = data.business.city, let state = data.business.state {
                    Text("\(city), \(state)")
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("TAX INVOICE")
                    .font(.system(size: 16, weight: .heavy))
                    .padding(.vertical, 2)
                HStack {
                    Text("Invoice No: \(data.invoice.invoiceNo)")
                        .fontWeight(.semibold)
                    Text("Date: \(Format.day(data.invoice.date))")
                }
            }
        }
    }

    private var buyerBlock: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Billed To").fontWeight(.semibold).foregroundStyle(.secondary)
                Text(data.customerName).fontWeight(.semibold)
                if let gstin = data.customerGstin, !gstin.isEmpty {
                    Text("GSTIN: \(gstin)")
                }
                if let address = data.customerAddress {
                    Text(address)
                }
                if let city = data.customerCity, let state = data.customerState {
                    Text("\(city), \(state)")
                }
                if let phone = data.customerPhone, !phone.isEmpty {
                    Text("Ph: \(phone)")
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 3) {
                Text("Dispatch").fontWeight(.semibold).foregroundStyle(.secondary)
                if let number = data.vehicleNumber {
                    Text("Vehicle: \(number)")
                }
                if let dispatch = data.dispatch {
                    if let net = dispatch.netKg {
                        Text("Net weight: \(Format.tonnesLabel(net))")
                    }
                    if let timeOut = dispatch.timeOut {
                        Text("Time out: \(Format.time(timeOut))")
                    }
                    if let loadedBy = dispatch.loadedBy, !loadedBy.isEmpty {
                        Text("Loaded by: \(loadedBy)")
                    }
                }
                if let place = data.invoice.placeOfSupply, !place.isEmpty {
                    Text("Place of supply: \(place)")
                }
            }
        }
    }

    private var itemsBlock: some View {
        VStack(spacing: 0) {
            headerRow
                .fontWeight(.bold)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.06))
            ForEach(data.items) { line in
                itemRow(line)
                    .padding(.vertical, 3)
                Divider()
            }
            if data.items.isEmpty {
                Text("No items")
                    .padding(.vertical, 6)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var headerRow: some View {
        HStack {
            Text("#").frame(width: 22, alignment: .leading)
            Text("Product").frame(width: 140, alignment: .leading)
            Text("HSN").frame(width: 48, alignment: .leading)
            Text("Qty (t)").frame(width: 62, alignment: .trailing)
            Text("Rate").frame(width: 76, alignment: .trailing)
            Text("GST%").frame(width: 42, alignment: .trailing)
            Text("Amount").frame(width: 92, alignment: .trailing)
        }
    }

    private func itemRow(_ line: InvoiceDocumentLine) -> some View {
        HStack {
            Text("\(line.index)").frame(width: 22, alignment: .leading)
            Text(line.productName).frame(width: 140, alignment: .leading)
            Text(line.hsn).frame(width: 48, alignment: .leading)
            Text(Format.tonnes(line.qtyKg)).frame(width: 62, alignment: .trailing)
            Text(Format.rupees(Double(line.ratePaisePerTonne) / 100)).frame(width: 76, alignment: .trailing)
            Text(Format.percent(bps: line.gstRateBps)).frame(width: 42, alignment: .trailing)
            Text(Format.rupees(Double(line.amountPaise) / 100)).frame(width: 92, alignment: .trailing)
        }
        .font(.system(size: 9.5))
    }

    private var totalsBlock: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                if let remarks = data.invoice.remarks, !remarks.isEmpty {
                    Text("Remarks: \(remarks)")
                        .foregroundStyle(.secondary)
                }
                Text("Amount in words: \(grandTotalInWords.uppercased())")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            totalsSummary
        }
    }

    private var totalsSummary: some View {
        VStack(spacing: 3) {
            totalRow("Subtotal", Format.rupees(Double(data.invoice.subtotalPaise) / 100))
            if data.invoice.cgstPaise > 0 {
                totalRow("CGST", Format.rupees(Double(data.invoice.cgstPaise) / 100))
                totalRow("SGST", Format.rupees(Double(data.invoice.sgstPaise) / 100))
            }
            if data.invoice.igstPaise > 0 {
                totalRow("IGST", Format.rupees(Double(data.invoice.igstPaise) / 100))
            }
            if data.invoice.transportChargePaise > 0 {
                totalRow("Transport", Format.rupees(Double(data.invoice.transportChargePaise) / 100))
            }
            if data.invoice.discountPaise > 0 {
                totalRow("Discount", "-\(Format.rupees(Double(data.invoice.discountPaise) / 100))")
            }
            Divider()
            HStack {
                Text("Grand Total")
                    .fontWeight(.bold)
                Spacer().frame(width: 40)
                Text(Format.rupees(Double(data.invoice.grandTotalPaise) / 100))
                    .fontWeight(.bold)
                    .frame(width: 92, alignment: .trailing)
            }
            .padding(.top, 2)
        }
        .frame(width: 280)
    }

    private func totalRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer().frame(width: 120)
            Text(value)
                .frame(width: 92, alignment: .trailing)
        }
        .frame(width: 280)
    }

    private var footer: some View {
        VStack(spacing: 3) {
            Divider()
                .padding(.top, 24)
            HStack {
                Text("This is a computer-generated invoice from PaashERP.")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("For \(data.business.name)")
                    .fontWeight(.semibold)
            }
            .padding(.top, 4)
        }
    }

    private var grandTotalInWords: String {
        let rupees = Double(data.invoice.grandTotalPaise) / 100
        return NumberToWords.inr(rupees)
    }
}

enum NumberToWords {
    private static let belowTwenty = [
        "", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten",
        "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen",
        "Eighteen", "Nineteen"
    ]
    private static let tens = [
        "", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"
    ]

    static func inr(_ amount: Double) -> String {
        let totalPaise = Int((amount * 100).rounded())
        let rupees = totalPaise / 100
        let paise = totalPaise % 100
        var words = rupees > 0 ? "Rupees \(twoDigitWords(for: rupees))" : ""
        if paise > 0 {
            if !words.isEmpty { words += " and " }
            words += "Paise \(twoDigitWords(for: paise))"
        }
        return words.isEmpty ? "Rupees Zero" : words
    }

    private static func twoDigitWords(for n: Int) -> String {
        guard n > 0 else { return "Zero" }
        return chunks(n).map { part -> String in
            let (value, label) = part
            return (value > 0 ? countWords(value) + (label.isEmpty ? "" : " \(label)") : "")
        }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private static func countWords(_ n: Int) -> String {
        if n < 20 { return belowTwenty[n] }
        if n < 100 { return tens[n / 10] + (n % 10 > 0 ? " " + belowTwenty[n % 10] : "") }
        if n < 1000 {
            return belowTwenty[n / 100] + " Hundred" + (n % 100 > 0 ? " " + countWords(n % 100) : "")
        }
        // `belowTwenty` only has 20 entries, so indexing it with `n / 100`
        // (as the < 1000 branch does) traps once a chunk reaches 2000 — which
        // the crore chunk can. Re-split into labelled units instead; every
        // resulting chunk is strictly smaller, so this always terminates.
        return twoDigitWords(for: n)
    }

    private static func chunks(_ n: Int) -> [(value: Int, label: String)] {
        var remaining = n
        var result: [(Int, String)] = []
        let units: [(Int, String)] = [
            (10000000, "Crore"), (100000, "Lakh"), (1000, "Thousand"), (100, "Hundred"), (1, "")
        ]
        for (value, label) in units {
            if remaining >= value {
                result.append((remaining / value, label))
                remaining %= value
            }
        }
        return result
    }
}

struct InvoiceDocumentLoader {
    static func load(_ db: Database, invoiceID: Int64) throws -> InvoiceDocumentData? {
        guard let invoice = try SalesInvoice.fetchOne(db, key: invoiceID) else { return nil }
        let customers = try Customer.fetchAll(db)
        let customer = customers.first { $0.id == invoice.customerId }
        let vehicles = try Vehicle.fetchAll(db)
        let vehicle = vehicles.first { $0.id == invoice.vehicleId }

        let items = try InvoiceItem.filter(Column("invoiceId") == invoiceID).order(Column("id")).fetchAll(db)
        let products = try Product.fetchAll(db)
        var productName = [Int64: String]()
        for product in products {
            if let id = product.id { productName[id] = product.name }
        }
        let lines = items.enumerated().map { index, item in
            InvoiceDocumentLine(
                index: index + 1,
                productName: productName[item.productId] ?? "Product #\(item.productId)",
                hsn: item.hsn,
                qtyKg: item.qtyKg,
                ratePaisePerTonne: item.ratePaisePerTonne,
                gstRateBps: item.gstRateBps,
                amountPaise: item.amountPaise
            )
        }
        let dispatch = try DispatchDetail.filter(Column("invoiceId") == invoiceID).fetchOne(db)

        let business = BusinessProfile(
            name: try AppSetting.value(forKey: "business_name", db: db) ?? "Stone Crusher Business Unit",
            gstin: try AppSetting.value(forKey: "business_gstin", db: db),
            address: try AppSetting.value(forKey: "business_address", db: db),
            city: try AppSetting.value(forKey: "business_city", db: db),
            state: try AppSetting.value(forKey: "business_state", db: db)
        )

        return InvoiceDocumentData(
            invoice: invoice,
            customerName: customer?.name ?? "Customer #\(invoice.customerId)",
            customerGstin: customer?.gstin,
            customerAddress: customer?.address,
            customerCity: customer?.city,
            customerState: customer?.state,
            customerPhone: customer?.phone,
            vehicleNumber: vehicle?.number,
            items: lines,
            dispatch: dispatch,
            business: business
        )
    }
}
struct InvoicePreviewSheet: View {
    let data: InvoiceDocumentData
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Invoice \(data.invoice.invoiceNo)")
                    .font(DS.Font.sectionTitle)
                Spacer()
                Button("Print…") { printInvoice() }
                Button("Export PDF…") { exportPDF() }
                    .buttonStyle(.borderedProminent)
                Button("Close") { dismiss() }
            }
            .padding(DS.Spacing.lg)
            Divider()
            ScrollView([.horizontal, .vertical]) {
                InvoiceDocumentView(data: data)
            }
        }
        .frame(width: 760, height: 820)
        .alert("Export failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func exportPDF() {
        guard let pdf = DocumentExport.pdfData(root: InvoiceDocumentView(data: data)) else { return }
        DocumentExport.save(
            pdf,
            suggestedName: "\(data.invoice.invoiceNo).pdf",
            fileType: .pdf
        ) { error in
            errorMessage = "Could not save the PDF: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func printInvoice() {
        let document = InvoiceDocumentView(data: data)
        let hosting = NSHostingView(rootView: document)
        let fitted = hosting.fittingSize
        let width = ceil(max(595, fitted.width))
        let height = ceil(max(842, fitted.height)) + 4
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()

        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.paperSize = NSSize(width: width, height: height)
        printInfo.orientation = .portrait
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic

        let operation = NSPrintOperation(view: hosting, printInfo: printInfo)
        operation.showsPrintPanel = true
        operation.run()
    }
}
