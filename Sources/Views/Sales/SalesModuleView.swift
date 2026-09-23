import SwiftUI
import GRDB

struct SalesInvoiceRow: Identifiable, Equatable {
    var id: Int64 { invoice.id ?? 0 }
    var invoice: SalesInvoice
    var customerName: String
    var vehicleNumber: String?
    var tonnesKg: Int64
}

enum InvoiceNumber {
    static func next(db: Database) throws -> String {
        let year = Calendar.autoupdatingCurrent.component(.year, from: .now)
        let prefix = "INV-\(year)-"
        let count = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM salesInvoices WHERE invoiceNo LIKE ?",
            arguments: [prefix + "%"]
        ) ?? 0
        return String(format: "%@%04d", prefix, count + 1)
    }
}

struct SalesModuleView: View {
    @Environment(\.appDatabase) private var db
    @State private var rows: [SalesInvoiceRow] = []
    @State private var selection: Int64?
    @State private var editor: SalesEditorContext?
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var previewData: InvoiceDocumentData?
    @State private var showPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            PageHeader(
                title: "Sales & Invoices",
                subtitle: "GST tax invoices with CGST/SGST/IGST, dispatch readings and automatic stock deduction."
            )

            if rows.isEmpty {
                EmptyStateView(
                    icon: "doc.text",
                    title: "No invoices yet",
                    message: "Create a tax invoice for a dispatch — enter the products, quantities, selling rate and transport charge. GST is computed automatically."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
            }
        }
        .padding(DS.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.contentBackground)
        .navigationTitle("Sales & Invoices")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    editor = SalesEditorContext(invoice: nil)
                } label: {
                    Label("New Invoice", systemImage: "plus")
                }
                Button {
                    if let row = selectedRow { previewInvoice(row.invoice) }
                } label: {
                    Label("PDF Preview", systemImage: "doc.richtext")
                }
                .disabled(selection == nil)
                Button {
                    if let row = selectedRow { startEditing(row) }
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .disabled(selection == nil)
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selection == nil)
            }
        }
        .sheet(item: $editor) { context in
            SalesEditorView(context: context) { reload() }
        }
        .sheet(isPresented: $showPreview) {
            if let previewData {
                InvoicePreviewSheet(data: previewData)
            }
        }
        .destructiveConfirmation(
            title: "Cancel this invoice?",
            message: "The invoiced quantity will be returned to stock. Invoices with recorded payments cannot be deleted.",
            destructiveLabel: "Cancel Invoice",
            isPresented: $confirmDelete
        ) { deleteSelected() }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task { reload() }
    }

    @ViewBuilder
    private var table: some View {
        Table(of: SalesInvoiceRow.self, selection: $selection) {
            TableColumn("Invoice") { row in
                Text(row.invoice.invoiceNo)
                    .font(DS.Font.bodySemibold)
            }
            .width(min: 100, ideal: 120)
            TableColumn("Date") { row in
                Text(Format.shortDate(row.invoice.date))
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 104)
            TableColumn("Customer") { row in
                Text(row.customerName)
            }
            TableColumn("Vehicle") { row in
                Text(row.vehicleNumber ?? "—")
                    .font(DS.Font.captionMono)
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 120)
            TableColumn("Quantity") { row in
                Text(Format.tonnesLabel(row.tonnesKg))
                    .font(DS.Font.tableValue)
            }
            .width(min: 90, ideal: 104)
            TableColumn("Status") { row in
                Badge(
                    text: row.invoice.status.label,
                    tint: row.invoice.status == .dispatched ? DS.Color.success : DS.Color.info
                )
            }
            .width(min: 90, ideal: 100)
            TableColumn("Total") { row in
                Text(Format.inr(row.invoice.grandTotalPaise))
                    .font(DS.Font.tableValue)
            }
            .width(min: 110, ideal: 130)
        } rows: {
            ForEach(rows) { (row: SalesInvoiceRow) in
                TableRow(row)
                    .contextMenu { rowContextMenu(row) }
            }
        }
        .alternatingRowBackgrounds()
        .contextMenu(forSelectionType: Int64.self) { selections in
            if let id = selections.first, let row = rows.first(where: { $0.id == id }) {
                Button("Edit") { startEditing(row) }
            }
            Button("Cancel Invoice", role: .destructive) { confirmDelete = true }
        }
    }

    private var selectedRow: SalesInvoiceRow? {
        guard let selection else { return nil }
        return rows.first { $0.id == selection }
    }

    private func previewInvoice(_ invoice: SalesInvoice) {
        guard let invoiceID = invoice.id else { return }
        do {
            previewData = try db.dbQueue.read { db in
                try InvoiceDocumentLoader.load(db, invoiceID: invoiceID)
            }
            showPreview = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startEditing(_ row: SalesInvoiceRow) {
        editor = SalesEditorContext(invoice: row.invoice)
    }

    private func rowContextMenu(_ row: SalesInvoiceRow) -> some View {
        Group {
            Button("Edit") { startEditing(row) }
            Button("Cancel Invoice", role: .destructive) {
                selection = row.id
                confirmDelete = true
            }
        }
    }

    private func deleteSelected() {
        guard let id = selection,
              let invoiceID = rows.first(where: { $0.id == id })?.invoice.id else { return }
        do {
            let canDelete = try db.dbQueue.read { db in
                try Payment.filter(Column("invoiceId") == invoiceID).fetchCount(db) == 0
            }
            guard canDelete else {
                errorMessage = "This invoice has payments recorded against it. Cancel or adjust the payments first."
                return
            }
            try db.dbQueue.write { db in
                try StockMovement
                    .filter(Column("type") == StockMovement.MoveType.sale.rawValue)
                    .filter(Column("refId") == invoiceID)
                    .deleteAll(db)
                try DispatchDetail.filter(Column("invoiceId") == invoiceID).deleteAll(db)
                try InvoiceItem.filter(Column("invoiceId") == invoiceID).deleteAll(db)
                try SalesInvoice.deleteOne(db, key: invoiceID)
            }
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() {
        do {
            rows = try db.dbQueue.read { db -> [SalesInvoiceRow] in
                let invoices = try SalesInvoice.order(Column("date").desc, Column("id").desc).fetchAll(db)
                let customers = try Customer.fetchAll(db)
                let vehicles = try Vehicle.fetchAll(db)
                var customerName = [Int64: String]()
                for customer in customers {
                    if let id = customer.id { customerName[id] = customer.name }
                }
                var vehicleNumber = [Int64: String]()
                for vehicle in vehicles {
                    if let id = vehicle.id { vehicleNumber[id] = vehicle.number }
                }
                let invoiceIDs = invoices.compactMap(\.id)
                var qtyByInvoice: [Int64: Int64] = [:]
                if invoiceIDs.isNotEmpty {
                    struct QtyRow: Decodable, FetchableRecord {
                        var invoiceId: Int64
                        var qtyKg: Int64
                    }
                    let qtyRows = try QtyRow.fetchAll(
                        db,
                        sql: "SELECT invoiceId, SUM(qtyKg) AS qtyKg FROM invoiceItems WHERE invoiceId IN (\(Array(repeating: "?", count: invoiceIDs.count).joined(separator: ","))) GROUP BY invoiceId",
                        arguments: StatementArguments(invoiceIDs)
                    )
                    for row in qtyRows {
                        qtyByInvoice[row.invoiceId] = row.qtyKg
                    }
                }
                return invoices.map { invoice in
                    SalesInvoiceRow(
                        invoice: invoice,
                        customerName: customerName[invoice.customerId] ?? "Unknown",
                        vehicleNumber: invoice.vehicleId.flatMap { vehicleNumber[$0] },
                        tonnesKg: qtyByInvoice[invoice.id ?? 0] ?? 0
                    )
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension Array {
    var isNotEmpty: Bool { !isEmpty }
}

struct SalesEditorContext: Identifiable {
    let id = UUID()
    let invoice: SalesInvoice?
}

struct InvoiceLineDraft: Identifiable {
    let id = UUID()
    var productId: Int64?
    var tonnesText = ""
    var rateText = ""

    var qtyKg: Int64 {
        let tonnes = Double(tonnesText.replacingOccurrences(of: ",", with: ".")) ?? 0
        return Int64((tonnes * 1000).rounded())
    }

    var ratePaisePerTonne: Int64 {
        let rupees = Double(rateText.replacingOccurrences(of: ",", with: ".")) ?? 0
        return Int64((rupees * 100).rounded())
    }

    var amountPaise: Int64 {
        qtyKg * ratePaisePerTonne / 1000
    }

    func gstPaise(bps: Int) -> Int64 {
        amountPaise * Int64(bps) / 10_000
    }
}

struct SalesEditorView: View {
    @Environment(\.appDatabase) private var db
    @Environment(\.dismiss) private var dismiss
    let context: SalesEditorContext
    let onSave: () -> Void

    @State private var invoiceNo: String
    @State private var date: Date
    @State private var customerId: Int64?
    @State private var vehicleId: Int64?
    @State private var state: String
    @State private var placeOfSupply: String
    @State private var transportText = ""
    @State private var discountText = ""
    @State private var remarks = ""
    @State private var lines: [InvoiceLineDraft] = []
    @State private var customers: [Customer] = []
    @State private var vehicles: [Vehicle] = []
    @State private var products: [Product] = []
    @State private var latestRates: [Int64: Int64] = [:]
    @State private var productById: [Int64: Product] = [:]
    @State private var businessState = ""
    @State private var errorMessage: String?

    init(context: SalesEditorContext, onSave: @escaping () -> Void) {
        self.context = context
        self.onSave = onSave
        let invoice = context.invoice ?? SalesInvoice(invoiceNo: "", date: .now, customerId: 0)
        _invoiceNo = State(initialValue: invoice.invoiceNo)
        _date = State(initialValue: invoice.date)
        _customerId = State(initialValue: invoice.customerId > 0 ? invoice.customerId : nil)
        _vehicleId = State(initialValue: invoice.vehicleId)
        _state = State(initialValue: invoice.state ?? "")
        _placeOfSupply = State(initialValue: invoice.placeOfSupply ?? "")
        _transportText = State(initialValue: String(format: "%.2f", Double(invoice.transportChargePaise) / 100))
        _discountText = State(initialValue: String(format: "%.2f", Double(invoice.discountPaise) / 100))
        _remarks = State(initialValue: invoice.remarks ?? "")
        _lines = State(initialValue: [])
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(context.invoice == nil ? "New Tax Invoice" : "Edit Invoice \(invoiceNo)")
                .font(DS.Font.sectionTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .horizontal], DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.s)

            Form {
                Section("Header") {
                    HStack {
                        TextField("Invoice number", text: $invoiceNo)
                            .disabled(context.invoice != nil)
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .fixedSize()
                    }
                    Picker("Customer", selection: $customerId) {
                        Text("Select customer").tag(Int64?.none)
                        ForEach(customers) { customer in
                            Text(customer.name).tag(Int64?(customer.id ?? 0))
                        }
                    }
                    Picker("Vehicle", selection: $vehicleId) {
                        Text("—").tag(Int64?.none)
                        ForEach(vehicles) { vehicle in
                            Text(vehicle.number).tag(Int64?(vehicle.id ?? 0))
                        }
                    }
                    TextField("Place of supply", text: $placeOfSupply)
                    TextField("State", text: $state)
                        .disabled(!state.isEmpty && context.invoice != nil)
                }

                Section("Items") {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                                Picker("Product", selection: lineProductBinding(index)) {
                                    Text("Select product").tag(Int64?.none)
                                    ForEach(products) { product in
                                        Text(product.name).tag(Int64?(product.id ?? 0))
                                    }
                                }
                                .frame(minWidth: 200)
                                TextField("Tonnes", text: lineTonnesBinding(index))
                                    .frame(width: 90)
                                    .multilineTextAlignment(.trailing)
                                TextField("₹/tonne", text: lineRateBinding(index))
                                    .frame(width: 90)
                                    .multilineTextAlignment(.trailing)
                                Button {
                                    removeLine(id: line.id)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(DS.Color.danger)
                                }
                                .buttonStyle(.plain)
                            }
                            HStack {
                                Text(lineAmount(index))
                                    .font(DS.Font.footnote)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if let product = productById[line.productId ?? 0], line.qtyKg > 0 {
                                    Text(Format.percent(bps: product.gstRateBps))
                                        .font(DS.Font.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    Button {
                        addLine()
                    } label: {
                        Label("Add line item", systemImage: "plus")
                    }
                    if lines.isEmpty {
                        Text("Add the crushed stone products being dispatched with quantity and rate.")
                            .font(DS.Font.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Charges") {
                    TextField("Transport charge (₹)", text: $transportText)
                    TextField("Discount (₹)", text: $discountText)
                }

                Section("Dispatch reading") {
                    TextField("Remarks", text: $remarks, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    totalsSummary
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                if let errorMessage {
                    Text(errorMessage)
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.Color.danger)
                        .lineLimit(2)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(DS.Spacing.lg)
        }
        .frame(width: 620)
        .padding(.top, DS.Spacing.s)
        .task { loadData() }
    }

    private var canSave: Bool {
        customerId != nil && lines.contains { $0.qtyKg > 0 && $0.ratePaisePerTonne > 0 }
    }

    private var transportPaise: Int64 {
        Int64((Double(transportText.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100)
    }

    private var discountPaise: Int64 {
        Int64((Double(discountText.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100)
    }

    private var subtotalPaise: Int64 {
        lines.reduce(0) { $0 + $1.amountPaise }
    }

    private var cgstPaise: Int64 {
        let intra = isIntraState
        return lines.reduce(0) { partial, line in
            guard let product = productById[line.productId ?? 0], intra else { return partial }
            return partial + line.gstPaise(bps: product.gstRateBps) / 2
        }
    }

    private var sgstPaise: Int64 {
        let intra = isIntraState
        return lines.reduce(0) { partial, line in
            guard let product = productById[line.productId ?? 0], intra else { return partial }
            let gst = line.gstPaise(bps: product.gstRateBps)
            return partial + gst - gst / 2
        }
    }

    private var igstPaise: Int64 {
        let intra = isIntraState
        return lines.reduce(0) { partial, line in
            guard let product = productById[line.productId ?? 0], !intra else { return partial }
            return partial + line.gstPaise(bps: product.gstRateBps)
        }
    }

    private var grandTotalPaise: Int64 {
        max(0, subtotalPaise + cgstPaise + sgstPaise + igstPaise + transportPaise - discountPaise)
    }

    private var isIntraState: Bool {
        let customerState = customers.first(where: { $0.id == customerId })?.state?.trimmingCharacters(in: .whitespaces)
        let business = businessState.trimmingCharacters(in: .whitespaces)
        if customerState == nil || business.isEmpty { return true }
        return customerState == business
    }

    @ViewBuilder
    private var totalsSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                totalRow("Subtotal", "subtotal")
                if cgstPaise > 0 {
                    totalRow("CGST", "cgst")
                    totalRow("SGST", "sgst")
                } else if igstPaise > 0 {
                    totalRow("IGST", "igst")
                }
                if transportPaise > 0 {
                    totalRow("Transport", "transport")
                }
                if discountPaise > 0 {
                    totalRow("Discount", "discount", negative: true)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: DS.Spacing.xs) {
                Text("Grand Total")
                    .font(DS.Font.footnote)
                    .foregroundStyle(.secondary)
                Text(Format.inr(grandTotalPaise))
                    .font(DS.Font.kpiValue)
            }
        }
    }

    private func totalRow(_ title: String, _ kind: String, negative: Bool = false) -> some View {
        HStack(spacing: DS.Spacing.m) {
            Text(title)
                .font(DS.Font.footnote)
                .foregroundStyle(.secondary)
            Text(valueFor(kind))
                .font(DS.Font.tableValue)
                .foregroundStyle(negative ? DS.Color.danger : .primary)
        }
    }

    private func valueFor(_ kind: String) -> String {
        switch kind {
        case "subtotal": Format.inr(subtotalPaise)
        case "cgst": Format.inr(cgstPaise)
        case "sgst": Format.inr(sgstPaise)
        case "igst": Format.inr(igstPaise)
        case "transport": Format.inr(transportPaise)
        default: Format.inr(-discountPaise)
        }
    }

    private func lineProductBinding(_ index: Int) -> Binding<Int64?> {
        Binding(
            get: { lines[index].productId },
            set: {
                lines[index].productId = $0
                if let pid = $0, lines[index].rateText.isEmpty, let rate = latestRates[pid] {
                    lines[index].rateText = String(format: "%.2f", Double(rate) / 100)
                }
            }
        )
    }

    private func lineTonnesBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { lines[index].tonnesText },
            set: { lines[index].tonnesText = $0 }
        )
    }

    private func lineRateBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { lines[index].rateText },
            set: { lines[index].rateText = $0 }
        )
    }

    private func lineAmount(_ index: Int) -> String {
        let line = lines[index]
        if line.amountPaise > 0 {
            return "\(Format.inr(line.amountPaise)) · \(Format.tonnesLabel(line.qtyKg))"
        }
        return "Enter quantity and rate"
    }

    private func addLine() {
        let used = Set(lines.compactMap(\.productId))
        let next = products.first { !used.contains($0.id ?? 0) }
        let rate = next.flatMap { latestRates[$0.id ?? 0] }
        lines.append(
            InvoiceLineDraft(
                productId: next?.id,
                rateText: rate.map { String(format: "%.2f", Double($0) / 100) } ?? ""
            )
        )
    }

    private func removeLine(id: UUID) {
        lines.removeAll { $0.id == id }
    }

    private func loadData() {
        do {
            let result = try db.dbQueue.read { db -> (customers: [Customer], vehicles: [Vehicle], products: [Product], rates: [Int64: Int64], businessState: String) in
                let customers = try Customer.filter(Column("isActive") == true).order(Column("name")).fetchAll(db)
                let vehicles = try Vehicle.filter(Column("isActive") == true).order(Column("number")).fetchAll(db)
                let products = try Product.filter(Column("isActive") == true).order(Column("sortOrder"), Column("name")).fetchAll(db)
                let allRates = try ProductRate.order(Column("id")).fetchAll(db)
                var latest: [Int64: Int64] = [:]
                for rate in allRates {
                    latest[rate.productId] = rate.ratePaisePerTonne
                }
                let businessState = try AppSetting.value(forKey: "business_state", db: db) ?? ""
                return (customers, vehicles, products, latest, businessState)
            }
            customers = result.customers
            vehicles = result.vehicles
            products = result.products
            latestRates = result.rates
            businessState = result.businessState
            var byId: [Int64: Product] = [:]
            for product in products {
                if let id = product.id { byId[id] = product }
            }
            productById = byId

            if state.isEmpty {
                state = result.businessState
            }

            if context.invoice != nil { loadExistingLines() }
            else if lines.isEmpty, let first = products.first {
                let rate = latestRates[first.id ?? 0]
                lines.append(
                    InvoiceLineDraft(
                        productId: first.id,
                        rateText: rate.map { String(format: "%.2f", Double($0) / 100) } ?? ""
                    )
                )
                _ = isIntraState
            } else if lines.isEmpty {
                addLine()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadExistingLines() {
        guard let invoiceID = context.invoice?.id else { return }
        do {
            let items = try db.dbQueue.read { db in
                try InvoiceItem.filter(Column("invoiceId") == invoiceID).fetchAll(db)
            }
            lines = items.map { item in
                InvoiceLineDraft(
                    productId: item.productId,
                    tonnesText: String(format: "%.3f", Double(item.qtyKg) / 1000),
                    rateText: String(format: "%.2f", Double(item.ratePaisePerTonne) / 100)
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard let customerID = customerId else { return }
        do {
            try db.dbQueue.write { db in
                var required: [Int64: Int64] = [:]
                for line in lines where line.qtyKg > 0 && line.ratePaisePerTonne > 0 && line.productId != nil {
                    guard let productID = line.productId else { continue }
                    required[productID, default: 0] += line.qtyKg
                }
                try StockGate.requireAvailable(
                    db: db,
                    replacingInvoiceID: context.invoice?.id,
                    required: required,
                    productName: { productById[$0]?.name }
                )

                let existing = context.invoice
                let resolvedNo: String
                if let existing {
                    resolvedNo = existing.invoiceNo
                } else if invoiceNo.isEmpty {
                    resolvedNo = try InvoiceNumber.next(db: db)
                } else {
                    resolvedNo = invoiceNo
                }
                var invoice = existing ?? SalesInvoice(
                    invoiceNo: resolvedNo,
                    date: date,
                    customerId: customerID
                )
                invoice.invoiceNo = resolvedNo
                invoice.date = date
                invoice.customerId = customerID
                invoice.vehicleId = vehicleId
                invoice.placeOfSupply = trimmedNil(placeOfSupply)
                invoice.state = trimmedNil(state)
                invoice.status = .dispatched
                invoice.subtotalPaise = subtotalPaise
                invoice.cgstPaise = cgstPaise
                invoice.sgstPaise = sgstPaise
                invoice.igstPaise = igstPaise
                invoice.transportChargePaise = transportPaise
                invoice.discountPaise = discountPaise
                invoice.grandTotalPaise = grandTotalPaise
                invoice.remarks = trimmedNil(remarks)
                invoice.updatedAt = .now
                if invoice.createdAt == .distantPast { invoice.createdAt = .now }
                try invoice.save(db)
                guard let invoiceID = invoice.id else { return }

                try StockMovement
                    .filter(Column("type") == StockMovement.MoveType.sale.rawValue)
                    .filter(Column("refId") == invoiceID)
                    .deleteAll(db)
                try InvoiceItem.filter(Column("invoiceId") == invoiceID).deleteAll(db)
                try DispatchDetail.filter(Column("invoiceId") == invoiceID).deleteAll(db)

                for line in lines where line.qtyKg > 0 && line.ratePaisePerTonne > 0 && line.productId != nil {
                    guard let productID = line.productId else { continue }
                    let product = productById[productID]
                    var item = InvoiceItem(
                        invoiceId: invoiceID,
                        productId: productID,
                        qtyKg: line.qtyKg,
                        ratePaisePerTonne: line.ratePaisePerTonne,
                        amountPaise: line.amountPaise,
                        gstRateBps: product?.gstRateBps ?? 0,
                        hsn: product?.hsn ?? ""
                    )
                    try item.insert(db)
                    var move = StockMovement(
                        productId: productID,
                        date: date,
                        type: .sale,
                        qtyKg: -line.qtyKg,
                        refId: invoiceID
                    )
                    try move.insert(db)
                }

                var dispatch = DispatchDetail(
                    invoiceId: invoiceID,
                    netKg: lines.reduce(0) { $0 + $1.qtyKg }
                )
                try dispatch.insert(db)
            }
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func trimmedNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}