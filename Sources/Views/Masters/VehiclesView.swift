import SwiftUI
import GRDB

struct VehicleRowModel: Identifiable, Equatable {
    var vehicle: Vehicle
    var id: Int64 { vehicle.id ?? 0 }
}

struct VehiclesView: View {
    @Environment(\.appDatabase) private var db
    @State private var rows: [VehicleRowModel] = []
    @State private var search = ""
    @State private var selection: Int64?
    @State private var editor: VehicleEditorContext?
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    private var filteredRows: [VehicleRowModel] {
        guard !search.isEmpty else { return rows }
        return rows.filter {
            $0.vehicle.number.localizedCaseInsensitiveContains(search)
                || ($0.vehicle.driverName ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        Group {
            if filteredRows.isEmpty {
                EmptyStateView(
                    icon: "truck",
                    title: search.isEmpty ? "No vehicles yet" : "No matches for “\(search)”",
                    message: "Own and hired tippers of the fleet, with drivers and capacities."
                )
            } else {
                table
            }
        }
        .searchable(text: $search, prompt: "Search vehicles or drivers")
        .navigationTitle("Vehicles")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    editor = VehicleEditorContext(vehicle: nil)
                } label: {
                    Label("Add Vehicle", systemImage: "plus")
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
            VehicleEditorView(context: context) { reload() }
        }
        .destructiveConfirmation(
            title: "Delete vehicle?",
            message: "Existing invoices keep their vehicle reference.",
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
        Table(of: VehicleRowModel.self, selection: $selection) {
            TableColumn("Vehicle") { row in
                Text(row.vehicle.number)
                    .font(DS.Font.bodySemibold)
            }
            .width(min: 120, ideal: 150)
            TableColumn("Ownership") { row in
                Badge(
                    text: row.vehicle.ownership.label,
                    tint: Self.ownershipTint(row.vehicle.ownership)
                )
            }
            .width(min: 90, ideal: 110)
            TableColumn("Capacity") { row in
                Text(Format.tonnesLabel(row.vehicle.capacityKg))
                    .font(DS.Font.tableValue)
            }
            .width(min: 90, ideal: 110)
            TableColumn("Driver") { row in
                Text(row.vehicle.driverName ?? "—")
            }
            TableColumn("Driver phone") { row in
                Text(row.vehicle.driverPhone ?? "—")
                    .font(DS.Font.captionMono)
                    .foregroundStyle(.secondary)
            }
            TableColumn("Status") { row in
                Badge(
                    text: row.vehicle.isActive ? "Active" : "Inactive",
                    tint: DS.Color.status(row.vehicle.isActive)
                )
            }
            .width(min: 80, ideal: 90)
        } rows: {
            ForEach(filteredRows) { (row: VehicleRowModel) in
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

    private var selectedRow: VehicleRowModel? {
        guard let selection else { return nil }
        return rows.first { $0.id == selection }
    }

    private static func ownershipTint(_ ownership: Vehicle.Ownership) -> SwiftUI.Color {
        if ownership == .own {
            return DS.Color.info
        }
        return DS.Color.accent
    }

    private func startEditing(_ row: VehicleRowModel) {
        editor = VehicleEditorContext(vehicle: row.vehicle)
    }

    private func rowContextMenu(_ row: VehicleRowModel) -> some View {
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
              let vehicleID = row.vehicle.id else { return }
        do {
            try db.dbQueue.write { db in
                try Vehicle.deleteOne(db, key: vehicleID)
            }
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() {
        do {
            rows = try db.dbQueue.read { db in
                try Vehicle.order(Column("number")).fetchAll(db).map(VehicleRowModel.init)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct VehicleEditorContext: Identifiable {
    let id = UUID()
    let vehicle: Vehicle?
}

struct VehicleEditorView: View {
    @Environment(\.appDatabase) private var db
    @Environment(\.dismiss) private var dismiss
    let context: VehicleEditorContext
    let onSave: () -> Void

    @State private var number: String
    @State private var ownership: Vehicle.Ownership
    @State private var capacity: String
    @State private var driverName: String
    @State private var driverPhone: String
    @State private var isActive: Bool
    @State private var errorMessage: String?

    init(context: VehicleEditorContext, onSave: @escaping () -> Void) {
        self.context = context
        self.onSave = onSave
        let vehicle = context.vehicle ?? Vehicle(number: "")
        _number = State(initialValue: vehicle.number)
        _ownership = State(initialValue: vehicle.ownership)
        _capacity = State(initialValue: String(format: "%.0f", Double(vehicle.capacityKg) / 1000.0))
        _driverName = State(initialValue: vehicle.driverName ?? "")
        _driverPhone = State(initialValue: vehicle.driverPhone ?? "")
        _isActive = State(initialValue: vehicle.isActive)
    }

    private var canSave: Bool {
        !number.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var capacityKg: Int64 {
        guard let tonnes = Double(capacity.trimmingCharacters(in: .whitespaces)) else { return 20_000 }
        return Int64((tonnes * 1000).rounded())
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(context.vehicle == nil ? "Add Vehicle" : "Edit Vehicle")
                .font(DS.Font.sectionTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .horizontal], DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.m)

            Form {
                TextField("Registration number", text: $number)
                    .textFieldStyle(.roundedBorder)
                Picker("Ownership", selection: $ownership) {
                    ForEach(Vehicle.Ownership.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                TextField("Capacity (tonnes)", text: $capacity)
                    .textFieldStyle(.roundedBorder)
                TextField("Driver name", text: $driverName)
                    .textFieldStyle(.roundedBorder)
                TextField("Driver phone", text: $driverPhone)
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
                var vehicle = context.vehicle ?? Vehicle(number: "")
                vehicle.number = number.trimmingCharacters(in: .whitespaces).uppercased()
                vehicle.ownership = ownership
                vehicle.capacityKg = capacityKg
                vehicle.driverName = trimmedOrNil(driverName)
                vehicle.driverPhone = trimmedOrNil(driverPhone)
                vehicle.isActive = isActive
                if vehicle.id == nil {
                    vehicle.createdAt = .now
                }
                vehicle.updatedAt = .now
                try vehicle.save(db)
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