import SwiftUI
import GRDB

struct CustomerRowModel: Identifiable, Equatable {
    var customer: Customer
    var outstandingPaise: Int64 = 0
    var id: Int64 { customer.id ?? 0 }
}

struct CustomersView: View {
    @Environment(\.appDatabase) private var db
    @State private var rows: [CustomerRowModel] = []
    @State private var search = ""
    @State private var selection: Int64?
    @State private var editor: CustomerEditorContext?
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    private var filteredRows: [CustomerRowModel] {
        guard !search.isEmpty else { return rows }
        return rows.filter {
            $0.customer.name.localizedCaseInsensitiveContains(search)
                || ($0.customer.city ?? "").localizedCaseInsensitiveContains(search)
                || ($0.customer.gstin ?? "").lowercased().contains(search.lowercased())
        }
    }

    var body: some View {
        Group {
            if filteredRows.isEmpty {
                EmptyStateView(
                    icon: "person.2",
                    title: search.isEmpty ? "No customers yet" : "No matches for “\(search)”",
                    message: "Add the buyers of your aggregates — contractors, builders, RMC plants and government projects."
                )
            } else {
                table
            }
        }
        .searchable(text: $search, prompt: "Search customers")
        .navigationTitle("Customers")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    editor = CustomerEditorContext(customer: nil)
                } label: {
                    Label("Add Customer", systemImage: "plus")
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
            CustomerEditorView(context: context) { reload() }
        }
        .destructiveConfirmation(
            title: "Delete customer?",
            message: "Customers without invoices are removed. Those with records are deactivated instead — existing invoices keep their customer snapshot.",
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
        Table(of: CustomerRowModel.self, selection: $selection) {
            TableColumn("Customer") { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.customer.name)
                        .font(DS.Font.bodySemibold)
                    if let gstin = row.customer.gstin, !gstin.isEmpty {
                        Text(gstin)
                            .font(DS.Font.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            TableColumn("City") { row in
                Text(row.customer.city ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 140)
            TableColumn("Phone") { row in
                Text(row.customer.phone ?? "—")
                    .font(DS.Font.captionMono)
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 130)
            TableColumn("Credit limit") { row in
                Text(Format.inr(row.customer.creditLimitPaise))
                    .font(DS.Font.tableValue)
            }
            TableColumn("Opening") { row in
                Text(Format.inr(row.customer.openingBalancePaise))
                    .font(DS.Font.tableValue)
            }
            TableColumn("Outstanding") { row in
                if row.outstandingPaise > 0 {
                    Text(Format.inr(row.outstandingPaise))
                        .font(DS.Font.tableValue)
                        .foregroundStyle(DS.Color.danger)
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 110, ideal: 130)
            TableColumn("Status") { row in
                Badge(
                    text: row.customer.isActive ? "Active" : "Inactive",
                    tint: DS.Color.status(row.customer.isActive)
                )
            }
            .width(min: 80, ideal: 90)
        } rows: {
            ForEach(filteredRows) { (row: CustomerRowModel) in
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

    private var selectedRow: CustomerRowModel? {
        guard let selection else { return nil }
        return rows.first { $0.id == selection }
    }

    private func startEditing(_ row: CustomerRowModel) {
        editor = CustomerEditorContext(customer: row.customer)
    }

    private func rowContextMenu(_ row: CustomerRowModel) -> some View {
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
              let row = rows.first(where: { $0.id == id }),
              let customerID = row.customer.id else { return }
        do {
            let outcome = try db.dbQueue.write { db in
                try MasterDeletion.delete(Customer.self, id: customerID, db: db)
            }
            if outcome == .deactivated {
                errorMessage = "“\(row.customer.name)” has invoices or payments on record, so it was deactivated instead of deleted."
            }
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() {
        do {
            rows = try db.dbQueue.read { db in
                let customers = try Customer.order(Column("name")).fetchAll(db)
                struct PartyTotals: Decodable, FetchableRecord {
                    var partyId: Int64
                    var amountPaise: Int64
                }
                let cancelled = SalesInvoice.Status.cancelled.rawValue
                let invoicedRows = try PartyTotals.fetchAll(
                    db,
                    sql: "SELECT customerId AS partyId, SUM(grandTotalPaise) AS amountPaise FROM salesInvoices WHERE status != ? GROUP BY customerId",
                    arguments: [cancelled]
                )
                let paidRows = try PartyTotals.fetchAll(
                    db,
                    sql: "SELECT partyId, SUM(amountPaise) AS amountPaise FROM payments WHERE partyType = ? GROUP BY partyId",
                    arguments: [Payment.PartyType.customer.rawValue]
                )
                var invoiced: [Int64: Int64] = [:]
                for row in invoicedRows { invoiced[row.partyId] = row.amountPaise }
                var paid: [Int64: Int64] = [:]
                for row in paidRows { paid[row.partyId] = row.amountPaise }
                return customers.map { customer in
                    let id = customer.id ?? 0
                    let outstanding = max(0, (invoiced[id] ?? 0) - (paid[id] ?? 0) + customer.openingBalancePaise)
                    return CustomerRowModel(customer: customer, outstandingPaise: outstanding)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CustomerEditorContext: Identifiable {
    let id = UUID()
    let customer: Customer?
}

struct CustomerEditorView: View {
    @Environment(\.appDatabase) private var db
    @Environment(\.dismiss) private var dismiss
    let context: CustomerEditorContext
    let onSave: () -> Void

    @State private var name: String
    @State private var gstin: String
    @State private var phone: String
    @State private var address: String
    @State private var city: String
    @State private var state: String
    @State private var creditLimit: String
    @State private var openingBalance: String
    @State private var isActive: Bool
    @State private var errorMessage: String?

    init(context: CustomerEditorContext, onSave: @escaping () -> Void) {
        self.context = context
        self.onSave = onSave
        let customer = context.customer ?? Customer(name: "")
        _name = State(initialValue: customer.name)
        _gstin = State(initialValue: customer.gstin ?? "")
        _phone = State(initialValue: customer.phone ?? "")
        _address = State(initialValue: customer.address ?? "")
        _city = State(initialValue: customer.city ?? "")
        _state = State(initialValue: customer.state ?? "")
        _creditLimit = State(initialValue: customer.creditLimitPaise == 0 ? "" : Format.rupeesWithoutSymbol(customer.creditLimitPaise))
        _openingBalance = State(initialValue: customer.openingBalancePaise == 0 ? "" : Format.rupeesWithoutSymbol(customer.openingBalancePaise))
        _isActive = State(initialValue: customer.isActive)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(context.customer == nil ? "Add Customer" : "Edit Customer")
                .font(DS.Font.sectionTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .horizontal], DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.m)

            Form {
                TextField("Party name", text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField("GSTIN (optional)", text: $gstin)
                    .textFieldStyle(.roundedBorder)
                TextField("Phone", text: $phone)
                    .textFieldStyle(.roundedBorder)
                TextField("Credit limit (₹ per month)", text: $creditLimit)
                    .textFieldStyle(.roundedBorder)
                TextField("Opening balance (₹)", text: $openingBalance)
                    .textFieldStyle(.roundedBorder)
                TextField("Address", text: $address, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                TextField("City", text: $city)
                    .textFieldStyle(.roundedBorder)
                TextField("State", text: $state)
                    .textFieldStyle(.roundedBorder)
                Toggle("In active use", isOn: $isActive)
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
        .frame(width: 460)
        .padding(.top, DS.Spacing.s)
    }

    private func save() {
        do {
            try db.dbQueue.write { db in
                var customer = context.customer ?? Customer(name: "")
                customer.name = name.trimmingCharacters(in: .whitespaces)
                customer.gstin = trimmedOrNil(gstin)
                customer.phone = trimmedOrNil(phone)
                customer.address = trimmedOrNil(address)
                customer.city = trimmedOrNil(city)
                customer.state = trimmedOrNil(state)
                customer.creditLimitPaise = parsedPaise(creditLimit)
                customer.openingBalancePaise = parsedPaise(openingBalance)
                customer.isActive = isActive
                if customer.id == nil {
                    customer.createdAt = .now
                }
                customer.updatedAt = .now
                try customer.save(db)
            }
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parsedPaise(_ value: String) -> Int64 {
        Format.paise(value)
    }
}