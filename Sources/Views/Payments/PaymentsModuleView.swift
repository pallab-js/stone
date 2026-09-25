import SwiftUI
import GRDB

struct PaymentRow: Identifiable, Equatable {
    var id: Int64 { payment.id ?? 0 }
    var payment: Payment
    var partyName: String
    var invoiceNo: String?
}

struct PaymentsModuleView: View {
    @Environment(\.appDatabase) private var db
    @Environment(AppState.self) private var appState
    @State private var rows: [PaymentRow] = []
    @State private var selection: Int64?
    @State private var editor: PaymentEditorContext?
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            PageHeader(
                title: "Payments",
                subtitle: "Cash, UPI, cheque and bank-transfer collections and settlements."
            )

            if rows.isEmpty {
                EmptyStateView(
                    icon: "indianrupeesign",
                    title: "No payments recorded",
                    message: "Record money received from customers or paid out to suppliers. Receivables and payables stay in sync automatically."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredRows.isEmpty {
                InlineEmptyState(
                    icon: "magnifyingglass",
                    title: "No matching payments",
                    message: "Nothing matches “\(searchText)”. Try party name, invoice or reference number."
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
        .navigationTitle("Payments")
        .loadingOverlay(!loaded)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search party, invoice or reference")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    editor = PaymentEditorContext(payment: nil)
                } label: {
                    Label("Record Payment", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                Button {
                    if let row = selectedRow { startEditing(row) }
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(selection == nil)
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(selection == nil)
            }
        }
        .sheet(item: $editor) { context in
            PaymentEditorView(context: context) { Task { await reload() } }
        }
        .destructiveConfirmation(
            title: "Delete this payment?",
            message: "The party balance will be recalculated without it.",
            destructiveLabel: "Delete",
            isPresented: $confirmDelete
        ) { Task { await deleteSelected() } }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await reload(); loaded = true }
        .onAppear { consumePendingPaymentDraft() }
    }

    /// Opens the payment editor pre-filled for a draft handed off from the
    /// Sales screen ("record payment against this invoice"), then clears the
    /// draft so it is not replayed on every appearance.
    private func consumePendingPaymentDraft() {
        guard let draft = appState.pendingPaymentDraft else { return }
        appState.pendingPaymentDraft = nil
        editor = PaymentEditorContext(
            payment: nil,
            prefillCustomerId: draft.customerId,
            prefillInvoiceId: draft.invoiceId,
            prefillAmountText: draft.amountHintPaise.map { String(format: "%.2f", Double($0) / 100) }
        )
    }

    @ViewBuilder
    private var table: some View {
        Table(of: PaymentRow.self, selection: $selection) {
            TableColumn("Date") { row in
                Text(Format.day(row.payment.date))
            }
            .width(min: 110, ideal: 130)
            TableColumn("Party") { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.partyName)
                    if let invoiceNo = row.invoiceNo {
                        Text(invoiceNo)
                            .font(DS.Font.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            TableColumn("Type") { row in
                VStack(alignment: .leading, spacing: 2) {
                    Badge(
                        text: row.payment.partyType == .customer ? "Received" : "Paid",
                        tint: row.payment.partyType == .customer ? DS.Color.success : DS.Color.warning
                    )
                    Text(row.payment.kind.label)
                        .font(DS.Font.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 105, ideal: 115)
            TableColumn("Mode") { row in
                Text(row.payment.mode.label)
                    .font(DS.Font.footnote)
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 110)
            TableColumn("Reference") { row in
                Text(row.payment.refNo ?? "—")
                    .font(DS.Font.captionMono)
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 130)
            TableColumn("Amount") { row in
                Text(Format.inr(row.payment.amountPaise))
                    .font(DS.Font.tableValue)
            }
            .width(min: 110, ideal: 130)
        } rows: {
            ForEach(filteredRows) { (row: PaymentRow) in
                TableRow(row)
                    .contextMenu { rowContextMenu(row) }
            }
        }
        .alternatingRowBackgrounds()
        .contextMenu(forSelectionType: Int64.self) { selections in
            // The menu can open over blank table area with an empty selection
            // (or without changing `selection`), so Delete must be scoped to
            // the right-clicked row rather than whatever row happens to be
            // selected.
            if let id = selections.first, let row = rows.first(where: { $0.id == id }) {
                Button("Edit") { startEditing(row) }
                Button("Delete", role: .destructive) {
                    selection = id
                    confirmDelete = true
                }
            }
        }
    }

    private var filteredRows: [PaymentRow] {
        guard !searchText.isEmpty else { return rows }
        let query = searchText.trimmingCharacters(in: .whitespaces).localizedLowercase
        return rows.filter { row in
            row.partyName.localizedLowercase.contains(query)
                || (row.invoiceNo?.localizedLowercase.contains(query) ?? false)
                || (row.payment.refNo?.localizedLowercase.contains(query) ?? false)
                || row.payment.mode.label.localizedLowercase.contains(query)
                || row.payment.kind.label.localizedLowercase.contains(query)
        }
    }

    private var selectedRow: PaymentRow? {
        guard let selection else { return nil }
        return rows.first { $0.id == selection }
    }

    private func startEditing(_ row: PaymentRow) {
        editor = PaymentEditorContext(payment: row.payment)
    }

    private func rowContextMenu(_ row: PaymentRow) -> some View {
        Group {
            Button("Edit") { startEditing(row) }
            Button("Delete", role: .destructive) {
                selection = row.id
                confirmDelete = true
            }
        }
    }

    private func deleteSelected() async {
        guard let id = selection,
              let paymentID = rows.first(where: { $0.id == id })?.payment.id else { return }
        do {
            try await db.writeAsync { db in
                try Payment.deleteOne(db, key: paymentID)
            }
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() async {
        do {
            rows = try await db.readAsync { db -> [PaymentRow] in
                let payments = try Payment.order(Column("date").desc, Column("id").desc).fetchAll(db)
                let customers = try Customer.fetchAll(db)
                let suppliers = try Supplier.fetchAll(db)
                let invoices = try SalesInvoice.fetchAll(db)
                var customerName = [Int64: String]()
                for customer in customers {
                    if let id = customer.id { customerName[id] = customer.name }
                }
                var supplierName = [Int64: String]()
                for supplier in suppliers {
                    if let id = supplier.id { supplierName[id] = supplier.name }
                }
                var invoiceNo: [Int64: String] = [:]
                for invoice in invoices {
                    if let id = invoice.id { invoiceNo[id] = invoice.invoiceNo }
                }
                return payments.map { payment in
                    let partyName: String
                    switch payment.partyType {
                    case .customer: partyName = customerName[payment.partyId] ?? "Customer #\(payment.partyId)"
                    case .supplier: partyName = supplierName[payment.partyId] ?? "Supplier #\(payment.partyId)"
                    }
                    return PaymentRow(
                        payment: payment,
                        partyName: partyName,
                        invoiceNo: payment.invoiceId.flatMap { invoiceNo[$0] }
                    )
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PaymentEditorContext: Identifiable {
    let id = UUID()
    let payment: Payment?
    var prefillCustomerId: Int64? = nil
    var prefillInvoiceId: Int64? = nil
    var prefillAmountText: String? = nil
}

struct PaymentEditorView: View {
    @Environment(\.appDatabase) private var db
    @Environment(\.dismiss) private var dismiss
    let context: PaymentEditorContext
    let onSave: () -> Void

    @State private var date: Date
    @State private var partyType: Payment.PartyType
    @State private var partyId: Int64?
    @State private var kind: Payment.Kind
    @State private var invoiceId: Int64?
    @State private var amountText: String
    @State private var mode: Payment.Mode
    @State private var refNo: String
    @State private var notes: String
    @State private var customers: [Customer] = []
    @State private var suppliers: [Supplier] = []
    @State private var invoices: [SalesInvoice] = []
    @State private var errorMessage: String?

    init(context: PaymentEditorContext, onSave: @escaping () -> Void) {
        self.context = context
        self.onSave = onSave
        let payment = context.payment ?? Payment(date: .now, partyType: .customer, partyId: context.prefillCustomerId ?? 0, amountPaise: 0)
        _date = State(initialValue: payment.date)
        _partyType = State(initialValue: payment.partyType)
        _partyId = State(initialValue: context.prefillCustomerId ?? (payment.partyId > 0 ? payment.partyId : nil))
        _kind = State(initialValue: context.prefillInvoiceId != nil ? .againstInvoice : payment.kind)
        _invoiceId = State(initialValue: context.prefillInvoiceId ?? payment.invoiceId)
        _amountText = State(initialValue: context.prefillAmountText ?? String(format: "%.2f", Double(payment.amountPaise) / 100))
        _mode = State(initialValue: payment.mode)
        _refNo = State(initialValue: payment.refNo ?? "")
        _notes = State(initialValue: payment.notes ?? "")
    }

    private var amountPaise: Int64 {
        Format.paise(amountText)
    }

    /// Invoices for the currently selected customer only, so a payment can
    /// never be linked to another party's invoice.
    private var scopedInvoices: [SalesInvoice] {
        guard partyType == .customer, let partyID = partyId else { return [] }
        return invoices.filter { $0.customerId == partyID }
    }

    private var canSave: Bool {
        partyId != nil && amountPaise > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(context.payment == nil ? "Record Payment" : "Edit Payment")
                .font(DS.Font.sectionTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .horizontal], DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.s)

            Form {
                Section("Party") {
                    Picker("Direction", selection: $partyType) {
                        Text("Received (Customer)").tag(Payment.PartyType.customer)
                        Text("Paid (Supplier)").tag(Payment.PartyType.supplier)
                    }
                    .onChange(of: partyType) { _, _ in
                        partyId = nil
                        invoiceId = nil
                    }
                    .onChange(of: partyId) { _, _ in
                        invoiceId = nil
                    }
                    if partyType == .customer {
                        Picker("Customer", selection: $partyId) {
                            Text("Select customer").tag(Int64?.none)
                            ForEach(customers) { customer in
                                Text(customer.name).tag(Int64?(customer.id ?? 0))
                            }
                        }
                    } else {
                        Picker("Supplier", selection: $partyId) {
                            Text("Select supplier").tag(Int64?.none)
                            ForEach(suppliers) { supplier in
                                Text(supplier.name).tag(Int64?(supplier.id ?? 0))
                            }
                        }
                    }
                }

                Section("Details") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Type", selection: $kind) {
                        Text("Against invoice").tag(Payment.Kind.againstInvoice)
                        Text("Advance").tag(Payment.Kind.advance)
                        Text("Other").tag(Payment.Kind.other)
                    }
                    if partyType == .customer && kind == .againstInvoice {
                        Picker("Invoice", selection: $invoiceId) {
                            Text("General").tag(Int64?.none)
                            ForEach(scopedInvoices) { invoice in
                                Text("\(invoice.invoiceNo) · \(Format.inr(invoice.grandTotalPaise))")
                                    .tag(Int64?(invoice.id ?? 0))
                            }
                        }
                        if scopedInvoices.isEmpty {
                            Text("No invoices on record for this customer yet.")
                                .font(DS.Font.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextField("Amount (₹)", text: $amountText)
                    Picker("Mode", selection: $mode) {
                        ForEach(Payment.Mode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    TextField("Reference (optional)", text: $refNo)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...3)
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
                Button("Save") { Task { await save() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(DS.Spacing.lg)
        }
        .frame(width: DS.SheetWidth.editor)
        .padding(.top, DS.Spacing.s)
        .task { await loadData() }
    }

    private func loadData() async {
        do {
            let loaded = try await db.readAsync { db -> (customers: [Customer], suppliers: [Supplier], invoices: [SalesInvoice]) in
                let customers = try Customer.filter(Column("isActive") == true).order(Column("name")).fetchAll(db)
                let suppliers = try Supplier.filter(Column("isActive") == true).order(Column("name")).fetchAll(db)
                let invoices = try SalesInvoice
                    .filter(Column("status") != SalesInvoice.Status.cancelled.rawValue)
                    .order(Column("date").desc, Column("id").desc)
                    .fetchAll(db)
                return (customers, suppliers, invoices)
            }
            customers = loaded.customers
            suppliers = loaded.suppliers
            invoices = loaded.invoices
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        guard let partyID = partyId else { return }
        if partyType == .customer && kind == .againstInvoice,
           let invoiceID = invoiceId,
           let invoice = invoices.first(where: { $0.id == invoiceID }),
           invoice.customerId != partyID {
            errorMessage = "The selected invoice belongs to a different customer. Choose the correct invoice or leave it unassigned."
            return
        }
        let formDate = date
        let formPartyType = partyType
        let formKind = kind
        let formInvoiceId = (partyType == .customer && kind == .againstInvoice) ? invoiceId : nil
        let formAmount = amountPaise
        let formMode = mode
        let formRefNo = trimmedNil(refNo)
        let formNotes = trimmedNil(notes)
        let existingPayment = context.payment
        do {
            try await db.writeAsync { db in
                var payment = existingPayment ?? Payment(
                    date: formDate,
                    partyType: formPartyType,
                    partyId: partyID,
                    amountPaise: formAmount
                )
                payment.date = formDate
                payment.partyType = formPartyType
                payment.partyId = partyID
                payment.kind = formKind
                payment.invoiceId = formInvoiceId
                payment.amountPaise = formAmount
                payment.mode = formMode
                payment.refNo = formRefNo
                payment.notes = formNotes
                try payment.save(db)
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