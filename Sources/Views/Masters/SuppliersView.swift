import SwiftUI
import GRDB

struct SupplierRowModel: Identifiable, Equatable {
    var supplier: Supplier
    var id: Int64 { supplier.id ?? 0 }
}

struct SuppliersView: View {
    @Environment(\.appDatabase) private var db
    @State private var rows: [SupplierRowModel] = []
    @State private var errorMessage: String?

    var body: some View {
        MasterListView(
            rows: rows,
            navigationTitle: "Suppliers",
            searchPrompt: "Search suppliers",
            addLabel: "Add Supplier",
            emptyIcon: "truck.box",
            emptyTitle: "No suppliers yet",
            emptyMessage: "Diesel vendors, spare-part dealers, blasting contractors and labour providers.",
            deleteConfirmationTitle: "Delete supplier?",
            deleteConfirmationMessage: "Unused suppliers are removed. Those with purchase records are deactivated instead — existing purchases keep their supplier snapshot.",
            filter: { row, query in
                row.supplier.name.localizedCaseInsensitiveContains(query)
                    || (row.supplier.city ?? "").localizedCaseInsensitiveContains(query)
            },
            deactivationMessage: { row in
                "“\(row.supplier.name)” has purchase records, so it was deactivated instead of deleted."
            },
            makeNewContext: { SupplierEditorContext(supplier: nil) },
            makeEditContext: { SupplierEditorContext(supplier: $0.supplier) },
            editorSheet: { context, onSave in
                SupplierEditorView(context: context, onSave: onSave)
            },
            deleteEntity: { database, id in
                try MasterDeletion.delete(Supplier.self, id: id, db: database)
            },
            table: supplierTable,
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

    private func supplierTable(
        _ selection: Binding<Int64?>,
        _ rows: [SupplierRowModel],
        _ startEditing: @escaping (SupplierRowModel) -> Void,
        _ deleteRow: @escaping (SupplierRowModel) -> Void
    ) -> some View {
        Table(of: SupplierRowModel.self, selection: selection) {
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
            ForEach(rows) { (row: SupplierRowModel) in
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
        let formIsActive = isActive
        let existingSupplier = context.supplier
        do {
            try await db.writeAsync { db in
                var supplier = existingSupplier ?? Supplier(name: "")
                supplier.name = formName
                supplier.gstin = formGstin
                supplier.phone = formPhone
                supplier.address = formAddress
                supplier.city = formCity
                supplier.isActive = formIsActive
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