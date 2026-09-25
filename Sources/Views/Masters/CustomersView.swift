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
    @State private var errorMessage: String?

    var body: some View {
        MasterListView(
            rows: rows,
            navigationTitle: "Customers",
            searchPrompt: "Search customers",
            addLabel: "Add Customer",
            emptyIcon: "person.2",
            emptyTitle: "No customers yet",
            emptyMessage: "Add the buyers of your aggregates — contractors, builders, RMC plants and government projects.",
            deleteConfirmationTitle: "Delete customer?",
            deleteConfirmationMessage: "Customers without invoices are removed. Those with records are deactivated instead — existing invoices keep their customer snapshot.",
            filter: { row, query in
                row.customer.name.localizedCaseInsensitiveContains(query)
                    || (row.customer.city ?? "").localizedCaseInsensitiveContains(query)
                    || (row.customer.gstin ?? "").lowercased().contains(query.lowercased())
            },
            deactivationMessage: { row in
                "“\(row.customer.name)” has invoices or payments on record, so it was deactivated instead of deleted."
            },
            makeNewContext: { CustomerEditorContext(customer: nil) },
            makeEditContext: { CustomerEditorContext(customer: $0.customer) },
            editorSheet: { context, onSave in
                CustomerEditorView(context: context, onSave: onSave)
            },
            deleteEntity: { database, id in
                try MasterDeletion.delete(Customer.self, id: id, db: database)
            },
            table: customerTable,
            onReload: { await reload() }
        )
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func customerTable(
        _ selection: Binding<Int64?>,
        _ rows: [CustomerRowModel],
        _ startEditing: @escaping (CustomerRowModel) -> Void,
        _ deleteRow: @escaping (CustomerRowModel) -> Void
    ) -> some View {
        Table(of: CustomerRowModel.self, selection: selection) {
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
                    Text("Settled")
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.Color.success)
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
            ForEach(rows) { (row: CustomerRowModel) in
                TableRow(row)
                    .contextMenu {
                        Button("Edit") { startEditing(row) }
                        Button("Delete", role: .destructive) { deleteRow(row) }
                    }
            }
        }
        .alternatingRowBackgrounds()
        .contextMenu(forSelectionType: Int64.self) { selections in
            if let id = selections.first, let row = rows.first(where: { $0.id == id }) {
                Button("Edit") { startEditing(row) }
                Button("Delete", role: .destructive) { deleteRow(row) }
            }
        }
    }

    private func reload() async {
        do {
            rows = try await db.readAsync { db in
                let customers = try Customer.order(Column("name")).fetchAll(db)
                let receivables = try ReceivablesCalculator.snapshot(db: db)
                var outstanding: [Int64: Int64] = [:]
                for customer in receivables.byCustomer {
                    outstanding[customer.customerId] = customer.outstandingPaise
                }
                return customers.map { customer in
                    CustomerRowModel(
                        customer: customer,
                        outstandingPaise: outstanding[customer.id ?? 0] ?? 0
                    )
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
                Button("Save") { Task { await save() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(DS.Spacing.lg)
        }
        .frame(width: DS.SheetWidth.editor)
        .padding(.top, DS.Spacing.s)
    }

    private func save() async {
        let formName = name.trimmingCharacters(in: .whitespaces)
        let formGstin = trimmedOrNil(gstin)
        let formPhone = trimmedOrNil(phone)
        let formAddress = trimmedOrNil(address)
        let formCity = trimmedOrNil(city)
        let formState = trimmedOrNil(state)
        let formCreditLimit = parsedPaise(creditLimit)
        let formOpeningBalance = parsedPaise(openingBalance)
        let formIsActive = isActive
        let existingCustomer = context.customer
        do {
            try await db.writeAsync { db in
                var customer = existingCustomer ?? Customer(name: "")
                customer.name = formName
                customer.gstin = formGstin
                customer.phone = formPhone
                customer.address = formAddress
                customer.city = formCity
                customer.state = formState
                customer.creditLimitPaise = formCreditLimit
                customer.openingBalancePaise = formOpeningBalance
                customer.isActive = formIsActive
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