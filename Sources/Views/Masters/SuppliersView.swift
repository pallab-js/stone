import SwiftUI
import GRDB

struct SupplierRowModel: Identifiable, Equatable {
    var supplier: Supplier
    var id: Int64 { supplier.id ?? 0 }
}

struct SuppliersView: View {
    @Environment(\.appDatabase) private var db
    @State private var rows: [SupplierRowModel] = []
    @State private var search = ""
    @State private var selection: Int64?
    @State private var editor: SupplierEditorContext?
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    private var filteredRows: [SupplierRowModel] {
        guard !search.isEmpty else { return rows }
        return rows.filter {
            $0.supplier.name.localizedCaseInsensitiveContains(search)
                || ($0.supplier.city ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        Group {
            if filteredRows.isEmpty {
                EmptyStateView(
                    icon: "truck.box",
                    title: search.isEmpty ? "No suppliers yet" : "No matches for “\(search)”",
                    message: "Diesel vendors, spare-part dealers, blasting contractors and labour providers."
                )
            } else {
                table
            }
        }
        .searchable(text: $search, prompt: "Search suppliers")
        .navigationTitle("Suppliers")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    editor = SupplierEditorContext(supplier: nil)
                } label: {
                    Label("Add Supplier", systemImage: "plus")
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
            SupplierEditorView(context: context) { reload() }
        }
        .destructiveConfirmation(
            title: "Delete supplier?",
            message: "Unused suppliers are removed. Those with purchase records are deactivated instead — existing purchases keep their supplier snapshot.",
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
        Table(of: SupplierRowModel.self, selection: $selection) {
            TableColumn("Supplier") { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.supplier.name)
                        .font(DS.Font.bodySemibold)
                    if let gstin = row.supplier.gstin, !gstin.isEmpty {
                        Text(gstin)
                            .font(DS.Font.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            TableColumn("City") { row in
                Text(row.supplier.city ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 140)
            TableColumn("Phone") { row in
                Text(row.supplier.phone ?? "—")
                    .font(DS.Font.captionMono)
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 130)
            TableColumn("Status") { row in
                Badge(
                    text: row.supplier.isActive ? "Active" : "Inactive",
                    tint: DS.Color.status(row.supplier.isActive)
                )
            }
            .width(min: 80, ideal: 90)
        } rows: {
            ForEach(filteredRows) { (row: SupplierRowModel) in
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

    private var selectedRow: SupplierRowModel? {
        guard let selection else { return nil }
        return rows.first { $0.id == selection }
    }

    private func startEditing(_ row: SupplierRowModel) {
        editor = SupplierEditorContext(supplier: row.supplier)
    }

    private func rowContextMenu(_ row: SupplierRowModel) -> some View {
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
              let supplierID = row.supplier.id else { return }
        do {
            let outcome = try db.dbQueue.write { db in
                try MasterDeletion.delete(Supplier.self, id: supplierID, db: db)
            }
            if outcome == .deactivated {
                errorMessage = "“\(row.supplier.name)” has purchase records, so it was deactivated instead of deleted."
            }
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() {
        do {
            rows = try db.dbQueue.read { db in
                try Supplier.order(Column("name")).fetchAll(db).map(SupplierRowModel.init)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SupplierEditorContext: Identifiable {
    let id = UUID()
    let supplier: Supplier?
}

struct SupplierEditorView: View {
    @Environment(\.appDatabase) private var db
    @Environment(\.dismiss) private var dismiss
    let context: SupplierEditorContext
    let onSave: () -> Void

    @State private var name: String
    @State private var gstin: String
    @State private var phone: String
    @State private var address: String
    @State private var city: String
    @State private var isActive: Bool
    @State private var errorMessage: String?

    init(context: SupplierEditorContext, onSave: @escaping () -> Void) {
        self.context = context
        self.onSave = onSave
        let supplier = context.supplier ?? Supplier(name: "")
        _name = State(initialValue: supplier.name)
        _gstin = State(initialValue: supplier.gstin ?? "")
        _phone = State(initialValue: supplier.phone ?? "")
        _address = State(initialValue: supplier.address ?? "")
        _city = State(initialValue: supplier.city ?? "")
        _isActive = State(initialValue: supplier.isActive)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(context.supplier == nil ? "Add Supplier" : "Edit Supplier")
                .font(DS.Font.sectionTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .horizontal], DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.m)

            Form {
                TextField("Supplier name", text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField("GSTIN (optional)", text: $gstin)
                    .textFieldStyle(.roundedBorder)
                TextField("Phone", text: $phone)
                    .textFieldStyle(.roundedBorder)
                TextField("Address", text: $address, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                TextField("City", text: $city)
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
                var supplier = context.supplier ?? Supplier(name: "")
                supplier.name = name.trimmingCharacters(in: .whitespaces)
                supplier.gstin = trimmedOrNil(gstin)
                supplier.phone = trimmedOrNil(phone)
                supplier.address = trimmedOrNil(address)
                supplier.city = trimmedOrNil(city)
                supplier.isActive = isActive
                if supplier.id == nil {
                    supplier.createdAt = .now
                }
                supplier.updatedAt = .now
                try supplier.save(db)
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
}