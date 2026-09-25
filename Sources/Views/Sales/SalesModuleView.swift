import SwiftUI
import GRDB

struct SalesInvoiceRow: Identifiable, Equatable {
    var id: Int64 { invoice.id ?? 0 }
    var invoice: SalesInvoice
    var customerName: String
    var vehicleNumber: String?
    var tonnesKg: Int64
    var paidPaise: Int64

    var duePaise: Int64 { max(0, invoice.grandTotalPaise - paidPaise) }
}

struct SalesModuleView: View {
    @Environment(\.appDatabase) private var db
    @Environment(AppState.self) private var appState
    @State private var rows: [SalesInvoiceRow] = []
    @State private var selection: Int64?
    @State private var editor: SalesEditorContext?
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var previewData: InvoiceDocumentData?
    @State private var showPreview = false
    @State private var searchText = ""
    @State private var loaded = false

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
            } else if filteredRows.isEmpty {
                InlineEmptyState(
                    icon: "magnifyingglass",
                    title: "No matching invoices",
                    message: "Nothing matches “\(searchText)”. Try invoice number, customer name or vehicle number."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
            }
        }
        .padding(DS.Spacing.xl)
        .frame(maxWidth: 1280)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.contentBackground)
        .navigationTitle("Sales & Invoices")
        .loadingOverlay(!loaded)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search invoice no, customer or vehicle")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    editor = SalesEditorContext(invoice: nil)
                } label: {
                    Label("New Invoice", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                Button {
                    if let row = selectedRow { previewInvoice(row.invoice) }
                } label: {
                    Label("PDF Preview", systemImage: "doc.richtext")
                }
                .disabled(selection == nil || selectedRow?.invoice.status == .cancelled)
                Button {
                    if let row = selectedRow { startEditing(row) }
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(selection == nil || selectedRow?.invoice.status == .cancelled)
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Cancel Invoice", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(selection == nil || selectedRow?.invoice.status == .cancelled)
            }
        }
        .sheet(item: $editor) { context in
            SalesEditorView(context: context) { Task { await reload() } }
        }
        .sheet(isPresented: $showPreview) {
            if let previewData {
                InvoicePreviewSheet(data: previewData)
            }
        }
        .destructiveConfirmation(
            title: "Cancel this invoice?",
            message: "It will be marked cancelled, excluded from all sales and receivable figures, and its quantity returned to stock. Invoices with recorded payments cannot be cancelled.",
            destructiveLabel: "Cancel Invoice",
            isPresented: $confirmDelete
        ) { Task { await cancelSelected() } }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await reload(); loaded = true }
    }

    private var filteredRows: [SalesInvoiceRow] {
        guard !searchText.isEmpty else { return rows }
        let query = searchText.trimmingCharacters(in: .whitespaces).localizedLowercase
        return rows.filter { row in
            row.invoice.invoiceNo.localizedLowercase.contains(query)
                || row.customerName.localizedLowercase.contains(query)
                || (row.vehicleNumber?.localizedLowercase.contains(query) ?? false)
        }
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
                    tint: statusTint(row.invoice.status)
                )
            }
            .width(min: 90, ideal: 100)
            TableColumn("Total") { row in
                Text(Format.inr(row.invoice.grandTotalPaise))
                    .font(DS.Font.tableValue)
            }
            .width(min: 110, ideal: 130)
            TableColumn("Paid") { row in
                Text(Format.inr(row.paidPaise))
                    .font(DS.Font.tableValue)
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 120)
            TableColumn("Due") { row in
                if row.invoice.status == .cancelled {
                    Text("—").foregroundStyle(.tertiary)
                } else if row.duePaise > 0 {
                    Text(Format.inr(row.duePaise))
                        .font(DS.Font.tableValue)
                        .foregroundStyle(dueTint(row.duePaise))
                } else {
                    Text("Settled")
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.Color.success)
                }
            }
            .width(min: 100, ideal: 120)
        } rows: {
            ForEach(filteredRows) { (row: SalesInvoiceRow) in
                TableRow(row)
                    .contextMenu { rowContextMenu(row) }
            }
        }
        .alternatingRowBackgrounds()
        .contextMenu(forSelectionType: Int64.self) { selections in
            // `selections` may be empty (menu opened over blank table area) and
            // does not necessarily update `selection`, so the destructive action
            // must target the right-clicked row itself.
            if let id = selections.first, let row = rows.first(where: { $0.id == id }), row.invoice.status != .cancelled {
                Button("Edit") { startEditing(row) }
                Button("Cancel Invoice", role: .destructive) {
                    selection = id
                    confirmDelete = true
                }
            }
        }
    }

    private var selectedRow: SalesInvoiceRow? {
        guard let selection else { return nil }
        return rows.first { $0.id == selection }
    }

    private func previewInvoice(_ invoice: SalesInvoice) {
        guard let invoiceID = invoice.id else { return }
        Task {
            do {
                let data = try await db.readAsync { db in
                    try InvoiceDocumentLoader.load(db, invoiceID: invoiceID)
                }
                // The loader returns nil when the invoice is gone (deleted or
                // cancelled elsewhere); showing the sheet anyway would present
                // a blank page with no explanation.
                guard let data else {
                    errorMessage = "This invoice could not be loaded. It may have been deleted."
                    return
                }
                previewData = data
                showPreview = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startEditing(_ row: SalesInvoiceRow) {
        editor = SalesEditorContext(invoice: row.invoice)
    }

    private func rowContextMenu(_ row: SalesInvoiceRow) -> some View {
        Group {
            if row.invoice.status != .cancelled {
                Button("Edit") { startEditing(row) }
                if row.duePaise > 0 {
                    Button("Record payment…") {
                        appState.recordPayment(
                            draft: PaymentDraft(
                                customerId: row.invoice.customerId,
                                invoiceId: row.invoice.id,
                                amountHintPaise: row.duePaise
                            )
                        )
                    }
                }
                Button("Cancel Invoice", role: .destructive) {
                    selection = row.id
                    confirmDelete = true
                }
            }
        }
    }

    private func statusTint(_ status: SalesInvoice.Status) -> SwiftUI.Color {
        switch status {
        case .dispatched: DS.Color.success
        case .cancelled: DS.Color.danger
        case .drafted: DS.Color.info
        }
    }

    private func dueTint(_ duePaise: Int64) -> SwiftUI.Color {
        if duePaise == 0 { return DS.Color.success }
        return DS.Color.danger
    }

    private func cancelSelected() async {
        guard let id = selection,
              let row = rows.first(where: { $0.id == id }),
              let invoiceID = row.invoice.id,
              row.invoice.status != .cancelled else { return }
        do {
            let paymentCount = try await db.readAsync { db in
                try Payment.filter(Column("invoiceId") == invoiceID).fetchCount(db)
            }
            guard paymentCount == 0 else {
                errorMessage = "This invoice has payments recorded against it. Cancel or adjust the payments first."
                return
            }
            try await db.writeAsync { db in
                var invoice = try SalesInvoice.fetchOne(db, key: invoiceID)
                invoice?.status = .cancelled
                if let invoice { try invoice.update(db) }
                try StockMovement
                    .filter(Column("type") == StockMovement.MoveType.sale.rawValue)
                    .filter(Column("refId") == invoiceID)
                    .deleteAll(db)
            }
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() async {
        do {
            rows = try await db.readAsync { db -> [SalesInvoiceRow] in
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
                let receivables = try ReceivablesCalculator.snapshot(db: db)
                var paidByInvoice: [Int64: Int64] = [:]
                for customer in receivables.byCustomer {
                    for invoice in customer.invoices {
                        paidByInvoice[invoice.invoiceId] = invoice.paidPaise
                    }
                }
                return invoices.map { invoice in
                    SalesInvoiceRow(
                        invoice: invoice,
                        customerName: customerName[invoice.customerId] ?? "Unknown",
                        vehicleNumber: invoice.vehicleId.flatMap { vehicleNumber[$0] },
                        tonnesKg: qtyByInvoice[invoice.id ?? 0] ?? 0,
                        paidPaise: paidByInvoice[invoice.id ?? 0] ?? 0
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
        Format.kg(fromTonnes: tonnesText)
    }

    var ratePaisePerTonne: Int64 {
        Format.paise(rateText)
    }

    var amountPaise: Int64 {
        InvoiceCalculator.amountPaise(qtyKg: qtyKg, ratePaisePerTonne: ratePaisePerTonne)
    }
}

struct SalesEditorView: View {
    @Environment(\.appDatabase) private var db
    @Environment(\.dismiss) private var dismiss
    let context: SalesEditorContext
    let onSave: () -> Void

    /// The CGST/SGST vs IGST split this invoice was originally recorded with.
    /// Non-nil while editing a saved invoice: the recorded tax structure is
    /// immutable, so a later change to the customer's State in Masters can
    /// never silently rewrite a dispatched tax invoice's composition.
    private let pinnedSplitMode: InvoiceCalculator.SplitMode?

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
    @State private var outstandingByCustomer: [Int64: Int64] = [:]
    @State private var businessState = ""
    @State private var tareText = ""
    @State private var grossText = ""
    @State private var loadedByText = ""
    @State private var timeOutEnabled = false
    @State private var timeOut = Date()
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
        pinnedSplitMode = InvoiceCalculator.recordedSplitMode(
            cgstPaise: invoice.cgstPaise,
            sgstPaise: invoice.sgstPaise,
            igstPaise: invoice.igstPaise
        )
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
                    if context.invoice != nil {
                        Text("Invoice number is locked once the invoice is saved.")
                            .font(DS.Font.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Picker("Customer", selection: $customerId) {
                        Text("Select customer").tag(Int64?.none)
                        ForEach(customers) { customer in
                            Text(customer.name).tag(Int64?(customer.id ?? 0))
                        }
                    }
                    .onChange(of: customerId) { _, newValue in
                        guard let id = newValue,
                              let city = customers.first(where: { $0.id == id })?.city,
                              placeOfSupply.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        placeOfSupply = city
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
                    if !state.isEmpty && context.invoice != nil {
                        Text("State is locked because it drives the CGST/SGST or IGST split already recorded on this invoice.")
                            .font(DS.Font.footnote)
                            .foregroundStyle(.secondary)
                    }
                    gstModeFootnote
                }

                Section("Items") {
                    ForEach(lines) { line in
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                                Picker("Product", selection: lineProductBinding(line.id)) {
                                    Text("Select product").tag(Int64?.none)
                                    ForEach(products) { product in
                                        Text(product.name).tag(Int64?(product.id ?? 0))
                                    }
                                }
                                .frame(minWidth: 200)
                                TextField("Tonnes", text: lineTonnesBinding(line.id))
                                    .frame(width: 90)
                                    .multilineTextAlignment(.trailing)
                                TextField("₹/tonne", text: lineRateBinding(line.id))
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
                                Text(lineAmount(line.id))
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

                Section("Dispatch & weighbridge") {
                    TextField("Tare weight (kg)", text: $tareText)
                    TextField("Gross weight (kg)", text: $grossText)
                    TextField("Loaded by", text: $loadedByText)
                    Toggle("Record time out", isOn: $timeOutEnabled)
                    if timeOutEnabled {
                        DatePicker("Time out", selection: $timeOut, displayedComponents: [.date, .hourAndMinute])
                    }
                    Text("Net weight: \(Format.tonnesLabel(dispatchNetKg))")
                        .font(DS.Font.footnote)
                        .foregroundStyle(.secondary)
                    if let dispatchWeightWarning {
                        Label(dispatchWeightWarning, systemImage: "exclamationmark.triangle.fill")
                            .font(DS.Font.footnote)
                            .foregroundStyle(DS.Color.warning)
                    }
                }

                Section("Remarks") {
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
        .frame(width: DS.SheetWidth.editorWide)
        .padding(.top, DS.Spacing.s)
        .task { await loadData() }
    }

    private var canSave: Bool {
        guard customerId != nil else { return false }
        // At least one complete line (product + quantity + rate) is required.
        guard lines.contains(where: { $0.productId != nil && $0.qtyKg > 0 && $0.ratePaisePerTonne > 0 }) else {
            return false
        }
        // A line with a quantity but no product would be counted in the
        // printed totals yet never written to invoiceItems (nor deduct stock),
        // so refuse to save until it is completed or removed.
        return !lines.contains { $0.productId == nil && ($0.qtyKg > 0 || $0.ratePaisePerTonne > 0) }
    }

    private var tareKg: Int64? {
        parseKg(tareText)
    }

    private var grossKg: Int64? {
        parseKg(grossText)
    }

    /// Net weight read off the weighbridge, when both tare and gross are
    /// entered and gross exceeds tare.
    private var weighbridgeNetKg: Int64? {
        if let tare = tareKg, let gross = grossKg, gross > tare { return gross - tare }
        return nil
    }

    private var billedLineKg: Int64 {
        lines.reduce(0) { $0 + $1.qtyKg }
    }

    /// Net weight persisted to the dispatch record: the weighbridge reading
    /// when available, otherwise the sum of the line items.
    private var dispatchNetKg: Int64 {
        weighbridgeNetKg ?? billedLineKg
    }

    /// Warning shown when the weighbridge reading disagrees with the billed
    /// line quantities, so a tax invoice never ships a noticeably different
    /// net weight from what is billed.
    private var dispatchWeightWarning: String? {
        if let tare = tareKg, let gross = grossKg, gross <= tare {
            return "Gross (\(Format.tonnesLabel(gross))) must exceed tare (\(Format.tonnesLabel(tare)))."
        }
        guard let discrepancy = InvoiceCalculator.dispatchDiscrepancy(
            weighbridgeNetKg: weighbridgeNetKg,
            lineTotalKg: billedLineKg
        ) else { return nil }
        return "Weighbridge net \(Format.tonnesLabel(discrepancy.weighedKg)) doesn't match the billed quantity \(Format.tonnesLabel(discrepancy.billedKg))."
    }

    private func parseKg(_ text: String) -> Int64? {
        guard let value = Format.parse(text), value > 0 else { return nil }
        return Int64(value.rounded())
    }

    private var transportPaise: Int64 {
        Format.paise(transportText)
    }

    private var discountPaise: Int64 {
        Format.paise(discountText)
    }

    private var invoiceLines: [InvoiceCalculator.Line] {
        // Product-less drafts contribute nothing: they are not persisted and
        // must not inflate the totals shown on the invoice.
        lines.filter { $0.productId != nil }.map { draft in
            InvoiceCalculator.Line(
                qtyKg: draft.qtyKg,
                ratePaisePerTonne: draft.ratePaisePerTonne,
                gstRateBps: productById[draft.productId ?? 0]?.gstRateBps ?? 0
            )
        }
    }

    private var totals: InvoiceCalculator.Totals {
        InvoiceCalculator.totals(
            lines: invoiceLines,
            transportPaise: transportPaise,
            discountPaise: discountPaise,
            isIntraState: isIntraState
        )
    }

    private var subtotalPaise: Int64 { totals.subtotalPaise }

    private var cgstPaise: Int64 { totals.cgstPaise }

    private var sgstPaise: Int64 { totals.sgstPaise }

    private var igstPaise: Int64 { totals.igstPaise }

    private var grandTotalPaise: Int64 { totals.grandTotalPaise }

    private var isIntraState: Bool {
        if let pinnedSplitMode {
            return pinnedSplitMode == .intraState
        }
        let customerState = customers.first(where: { $0.id == customerId })?.state
        return InvoiceCalculator.isIntraState(customerState: customerState, businessState: businessState)
    }

    /// Explains which GST split this invoice will actually print. For a new
    /// invoice it is driven by the customer's registered state relative to the
    /// business state (not the "State" text field); for a saved invoice it is
    /// the split recorded when the invoice was dispatched and stays pinned.
    private var gstModeFootnote: some View {
        let hint: String
        if let pinnedSplitMode {
            hint = pinnedSplitMode == .intraState
                ? "Recorded as CGST + SGST (intra-state); editing keeps this split."
                : "Recorded as IGST (inter-state); editing keeps this split."
        } else {
            let customer = customerId.flatMap { id in customers.first(where: { $0.id == id }) }
            if customer == nil {
                hint = "Select a customer to determine whether CGST/SGST or IGST applies."
            } else if customer?.state?.trimmingCharacters(in: .whitespaces).isEmpty ?? true {
                hint = "Set the customer's State in Customers to determine CGST/SGST vs IGST."
            } else {
                hint = isIntraState
                    ? "Taxes will print as CGST + SGST (intra-state)."
                    : "Taxes will print as IGST (inter-state)."
            }
        }
        return Text(hint)
            .font(DS.Font.footnote)
            .foregroundStyle(.secondary)
    }

    /// Warns when this invoice would push the selected customer's exposure
    /// past their credit limit (0 = no limit). Replaces the existing invoice's
    /// total when editing so the exposure is not double-counted.
    private var creditWarning: String? {
        guard let customerID = customerId,
              let customer = customers.first(where: { $0.id == customerID }),
              customer.creditLimitPaise > 0 else { return nil }
        let existing = context.invoice?.grandTotalPaise ?? 0
        guard InvoiceCalculator.exceedsCreditLimit(
            creditLimitPaise: customer.creditLimitPaise,
            currentOutstandingPaise: outstandingByCustomer[customerID] ?? 0,
            newInvoiceTotalPaise: grandTotalPaise,
            existingInvoiceTotalPaise: existing
        ) else { return nil }
        return "This invoice pushes \(customer.name) beyond their \(Format.inr(customer.creditLimitPaise)) credit limit."
    }

    @ViewBuilder
    private var totalsSummary: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            if let creditWarning {
                Label(creditWarning, systemImage: "exclamationmark.triangle.fill")
                    .font(DS.Font.footnote)
                    .foregroundStyle(DS.Color.warning)
            }
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

    // Bindings are keyed by the line's id, never by its position: a captured
    // index is read/written before SwiftUI re-renders after a line is removed
    // (or after `lines` is replaced by a fresh load), which would trap with
    // "Index out of range" on the focused field.
    private func lineProductBinding(_ id: UUID) -> Binding<Int64?> {
        Binding(
            get: { lines.first(where: { $0.id == id })?.productId },
            set: { newValue in
                guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
                lines[index].productId = newValue
                if let pid = newValue, lines[index].rateText.isEmpty, let rate = latestRates[pid] {
                    lines[index].rateText = String(format: "%.2f", Double(rate) / 100)
                }
            }
        )
    }

    private func lineTonnesBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { lines.first(where: { $0.id == id })?.tonnesText ?? "" },
            set: { newValue in
                guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
                lines[index].tonnesText = newValue
            }
        )
    }

    private func lineRateBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { lines.first(where: { $0.id == id })?.rateText ?? "" },
            set: { newValue in
                guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
                lines[index].rateText = newValue
            }
        )
    }

    private func lineAmount(_ id: UUID) -> String {
        guard let line = lines.first(where: { $0.id == id }) else { return "" }
        if line.amountPaise > 0 {
            return "\(Format.inr(line.amountPaise)) · \(Format.tonnesLabel(line.qtyKg))"
        }
        return "Enter quantity and rate"
    }

    private func addLine() {
        let used = Set(lines.compactMap(\.productId))
        let next = products.first { $0.isActive && !used.contains($0.id ?? 0) }
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

    private func loadData() async {
        do {
            let result = try await db.readAsync { db -> (customers: [Customer], vehicles: [Vehicle], products: [Product], rates: [Int64: Int64], outstanding: [Int64: Int64], businessState: String) in
                let customers = try Customer.filter(Column("isActive") == true).order(Column("name")).fetchAll(db)
                let vehicles = try Vehicle.filter(Column("isActive") == true).order(Column("number")).fetchAll(db)
                // Every product, active or not: a deactivated product still on
                // this invoice must keep its GST rate and HSN, and the picker
                // has to be able to render the saved selection.
                let products = try Product.order(Column("sortOrder"), Column("name")).fetchAll(db)
                let allRates = try ProductRate.order(Column("id")).fetchAll(db)
                var latest: [Int64: Int64] = [:]
                for rate in allRates {
                    latest[rate.productId] = rate.ratePaisePerTonne
                }

                let receivables = try ReceivablesCalculator.snapshot(db: db)
                var outstanding: [Int64: Int64] = [:]
                for customer in receivables.byCustomer {
                    outstanding[customer.customerId] = customer.outstandingPaise
                }

                let businessState = try AppSetting.value(forKey: "business_state", db: db) ?? ""
                return (customers, vehicles, products, latest, outstanding, businessState)
            }
            customers = result.customers
            vehicles = result.vehicles
            products = result.products.filter(\.isActive)
            latestRates = result.rates
            outstandingByCustomer = result.outstanding
            businessState = result.businessState
            var byId: [Int64: Product] = [:]
            for product in result.products {
                if let id = product.id { byId[id] = product }
            }
            productById = byId

            if state.isEmpty {
                state = result.businessState
            }

            if context.invoice != nil {
                await loadExistingLines()
                await loadExistingDispatch()
            }
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
            products = pickerProducts(from: result.products)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Products offered in the line pickers: the active catalogue, plus any
    /// deactivated product this invoice already bills so its saved selection
    /// renders (and its GST/HSN stay resolvable) instead of showing blank.
    private func pickerProducts(from all: [Product]) -> [Product] {
        let active = all.filter(\.isActive)
        let activeIDs = Set(active.compactMap(\.id))
        let referenced = Set(lines.compactMap(\.productId)).subtracting(activeIDs)
        guard !referenced.isEmpty else { return active }
        return active + all.filter { referenced.contains($0.id ?? 0) }
    }

    private func loadExistingLines() async {
        guard let invoiceID = context.invoice?.id else { return }
        do {
            let items = try await db.readAsync { db in
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

    private func loadExistingDispatch() async {
        guard let invoiceID = context.invoice?.id else { return }
        do {
            guard let existing = try await db.readAsync({ db in
                try DispatchDetail.filter(Column("invoiceId") == invoiceID).fetchOne(db)
            }) else { return }
            if let tare = existing.tareKg { tareText = String(tare) }
            if let gross = existing.grossKg { grossText = String(gross) }
            loadedByText = existing.loadedBy ?? ""
            if let savedTimeOut = existing.timeOut {
                timeOutEnabled = true
                timeOut = savedTimeOut
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        if let existing = context.invoice, existing.status == .cancelled {
            errorMessage = "Cancelled invoices cannot be edited. Create a new invoice instead."
            return
        }
        guard let customerID = customerId else { return }
        let editingInvoice = context.invoice
        let userInvoiceNo = invoiceNo
        let formDate = date
        let formVehicleId = vehicleId
        let formPlaceOfSupply = trimmedNil(placeOfSupply)
        let formState = trimmedNil(state)
        let formRemarks = trimmedNil(remarks)
        let formSubtotal = subtotalPaise
        let formCGST = cgstPaise
        let formSGST = sgstPaise
        let formIGST = igstPaise
        let formTransport = transportPaise
        let formDiscount = discountPaise
        let formGrandTotal = grandTotalPaise
        let formTare = tareKg
        let formGross = grossKg
        let formNet = dispatchNetKg
        let formLoadedBy = trimmedNil(loadedByText)
        let formTimeOutEnabled = timeOutEnabled
        let formTimeOut = timeOut
        let formLines = lines
        let formProductById = productById
        Task {
            do {
                try await db.writeAsync { db in
                    var required: [Int64: Int64] = [:]
                    for line in formLines where line.qtyKg > 0 && line.ratePaisePerTonne > 0 && line.productId != nil {
                        guard let productID = line.productId else { continue }
                        required[productID, default: 0] += line.qtyKg
                    }
                    try StockGate.requireAvailable(
                        db: db,
                        replacingInvoiceID: editingInvoice?.id,
                        required: required,
                        productName: { formProductById[$0]?.name }
                    )

                    let resolvedNo: String
                    if let editingInvoice {
                        resolvedNo = editingInvoice.invoiceNo
                    } else if userInvoiceNo.isEmpty {
                        resolvedNo = try InvoiceNumber.next(db: db)
                    } else {
                        resolvedNo = userInvoiceNo
                    }
                    var invoice = editingInvoice ?? SalesInvoice(
                        invoiceNo: resolvedNo,
                        date: formDate,
                        customerId: customerID
                    )
                    invoice.invoiceNo = resolvedNo
                    invoice.date = formDate
                    invoice.customerId = customerID
                    invoice.vehicleId = formVehicleId
                    invoice.placeOfSupply = formPlaceOfSupply
                    invoice.state = formState
                    invoice.status = .dispatched
                    invoice.subtotalPaise = formSubtotal
                    invoice.cgstPaise = formCGST
                    invoice.sgstPaise = formSGST
                    invoice.igstPaise = formIGST
                    invoice.transportChargePaise = formTransport
                    invoice.discountPaise = formDiscount
                    invoice.grandTotalPaise = formGrandTotal
                    invoice.remarks = formRemarks
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

                    for line in formLines where line.qtyKg > 0 && line.ratePaisePerTonne > 0 && line.productId != nil {
                        guard let productID = line.productId else { continue }
                        let product = formProductById[productID]
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
                            date: formDate,
                            type: .sale,
                            qtyKg: -line.qtyKg,
                            refId: invoiceID
                        )
                        try move.insert(db)
                    }

                    var dispatch = DispatchDetail(
                        invoiceId: invoiceID,
                        tareKg: formTare,
                        grossKg: formGross,
                        netKg: formNet,
                        loadedBy: formLoadedBy,
                        timeOut: formTimeOutEnabled ? formTimeOut : nil
                    )
                    try dispatch.insert(db)
                }
                onSave()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func trimmedNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}