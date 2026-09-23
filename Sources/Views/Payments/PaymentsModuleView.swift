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
    @State private var rows: [PaymentRow] = []
    @State private var selection: Int64?
    @State private var editor: PaymentEditorContext?
    @State private var confirmDelete = false
    @State private var errorMessage: String?

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
            } else {
                table
            }
        }
        .padding(DS.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.contentBackground)
        .navigationTitle("Payments")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    editor = PaymentEditorContext(payment: nil)
                } label: {
                    Label("Record Payment", systemImage: "plus")
                }
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
            PaymentEditorView(context: context) { reload() }
        }
        .destructiveConfirmation(
            title: "Delete this payment?",
            message: "The party balance will be recalculated without it.",
            destructiveLabel: "Delete",
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
                Badge(
                    text: row.payment.partyType == .customer ? "Received" : "Paid",
                    tint: row.payment.partyType == .customer ? DS.Color.success : DS.Color.warning
                )
            }
            .width(min: 90, ideal: 100)
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
            ForEach(rows) { (row: PaymentRow) in
                TableRow(row)
                    .contextMenu { rowContextMenu(row) }
            }
        }
        .alternatingRowBackgrounds()
        .contextMenu(forSelectionType: Int64.self) { selections in
            if let id = selections.first, let row = rows.first(where: { $0.id == id }) {
                Button("Edit") { startEditing(row) }
            }
            Button("Delete", role: .destructive) { confirmDelete = true }
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

    private func deleteSelected() {
        guard let id = selection,
              let paymentID = rows.first(where: { $0.id == id })?.payment.id else { return }
        do {
            try db.dbQueue.write { db in
                try Payment.deleteOne(db, key: paymentID)
            }
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() {
        do {
            rows = try db.dbQueue.read { db -> [PaymentRow] in
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
        let payment = context.payment ?? Payment(date: .now, partyType: .customer, partyId: 0, amountPaise: 0)
        _date = State(initialValue: payment.date)
        _partyType = State(initialValue: payment.partyType)
        _partyId = State(initialValue: payment.partyId > 0 ? payment.partyId : nil)
        _kind = State(initialValue: payment.kind)
        _invoiceId = State(initialValue: payment.invoiceId)
        _amountText = State(initialValue: String(format: "%.2f", Double(payment.amountPaise) / 100))
        _mode = State(initialValue: payment.mode)
        _refNo = State(initialValue: payment.refNo ?? "")
        _notes = State(initialValue: payment.notes ?? "")
    }

    private var amountPaise: Int64 {
        Int64((Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100)
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
                            ForEach(invoices) { invoice in
                                Text("\(invoice.invoiceNo) · \(Format.inr(invoice.grandTotalPaise))")
                                    .tag(Int64?(invoice.id ?? 0))
                            }
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
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(DS.Spacing.lg)
        }
        .frame(width: 520)
        .padding(.top, DS.Spacing.s)
        .task { loadData() }
    }

    private func loadData() {
        do {
            let loaded = try db.dbQueue.read { db -> (customers: [Customer], suppliers: [Supplier], invoices: [SalesInvoice]) in
                let customers = try Customer.filter(Column("isActive") == true).order(Column("name")).fetchAll(db)
                let suppliers = try Supplier.filter(Column("isActive") == true).order(Column("name")).fetchAll(db)
                let invoices = try SalesInvoice.order(Column("date").desc, Column("id").desc).fetchAll(db)
                return (customers, suppliers, invoices)
            }
            customers = loaded.customers
            suppliers = loaded.suppliers
            if partyType == .customer {
                invoices = loaded.invoices
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard let partyID = partyId else { return }
        do {
            try db.dbQueue.write { db in
                var payment = context.payment ?? Payment(
                    date: date,
                    partyType: partyType,
                    partyId: partyID,
                    amountPaise: amountPaise
                )
                payment.date = date
                payment.partyType = partyType
                payment.partyId = partyID
                payment.kind = kind
                payment.invoiceId = (partyType == .customer && kind == .againstInvoice) ? invoiceId : nil
                payment.amountPaise = amountPaise
                payment.mode = mode
                payment.refNo = trimmedNil(refNo)
                payment.notes = trimmedNil(notes)
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