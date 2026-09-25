import SwiftUI
import GRDB

struct VehicleRowModel: Identifiable, Equatable {
    var vehicle: Vehicle
    var id: Int64 { vehicle.id ?? 0 }
}

struct VehiclesView: View {
    @Environment(\.appDatabase) private var db
    @State private var rows: [VehicleRowModel] = []
    @State private var errorMessage: String?

    var body: some View {
        MasterListView(
            rows: rows,
            navigationTitle: "Vehicles",
            searchPrompt: "Search vehicles or drivers",
            addLabel: "Add Vehicle",
            emptyIcon: "truck.pickup.side",
            emptyTitle: "No vehicles yet",
            emptyMessage: "Own and hired tippers of the fleet, with drivers and capacities.",
            deleteConfirmationTitle: "Delete vehicle?",
            deleteConfirmationMessage: "Unused vehicles are removed. Those used on invoices are deactivated instead — existing invoices keep their vehicle number.",
            filter: { row, query in
                row.vehicle.number.localizedCaseInsensitiveContains(query)
                    || (row.vehicle.driverName ?? "").localizedCaseInsensitiveContains(query)
            },
            deactivationMessage: { row in
                "“\(row.vehicle.number)” is used on invoices, so it was deactivated instead of deleted."
            },
            makeNewContext: { VehicleEditorContext(vehicle: nil) },
            makeEditContext: { VehicleEditorContext(vehicle: $0.vehicle) },
            editorSheet: { context, onSave in
                VehicleEditorView(context: context, onSave: onSave)
            },
            deleteEntity: { database, id in
                try MasterDeletion.delete(Vehicle.self, id: id, db: database)
            },
            table: vehicleTable,
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

    private func vehicleTable(
        _ selection: Binding<Int64?>,
        _ rows: [VehicleRowModel],
        _ startEditing: @escaping (VehicleRowModel) -> Void,
        _ deleteRow: @escaping (VehicleRowModel) -> Void
    ) -> some View {
        Table(of: VehicleRowModel.self, selection: selection) {
            TableColumn("Vehicle") { row in
                Text(row.vehicle.number)
                    .font(DS.Font.bodySemibold)
            }
            .width(min: 120, ideal: 150)
            TableColumn("Ownership") { row in
                Badge(
                    text: row.vehicle.ownership.label,
                    tint: VehiclesView.ownershipTint(row.vehicle.ownership)
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
            ForEach(rows) { (row: VehicleRowModel) in
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

    private static func ownershipTint(_ ownership: Vehicle.Ownership) -> SwiftUI.Color {
        if ownership == .own {
            return DS.Color.info
        }
        return DS.Color.accent
    }

    private func reload() async {
        do {
            rows = try await db.readAsync { db in
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
        // %.3f preserves the stored kilogram precision (12,500 kg → "12.5");
        // %.0f would round-trip it back as 12,000 kg on the next save.
        _capacity = State(initialValue: String(format: "%.3f", Double(vehicle.capacityKg) / 1000.0))
        _driverName = State(initialValue: vehicle.driverName ?? "")
        _driverPhone = State(initialValue: vehicle.driverPhone ?? "")
        _isActive = State(initialValue: vehicle.isActive)
    }

    private var canSave: Bool {
        !number.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var capacityKg: Int64 {
        // An unparseable field keeps the vehicle's current capacity instead of
        // silently overwriting it with the 20 t default.
        guard let tonnes = Format.parse(capacity) else { return context.vehicle?.capacityKg ?? 20_000 }
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
        let formNumber = number.trimmingCharacters(in: .whitespaces).uppercased()
        let formOwnership = ownership
        let formCapacityKg = capacityKg
        let formDriverName = trimmedOrNil(driverName)
        let formDriverPhone = trimmedOrNil(driverPhone)
        let formIsActive = isActive
        let existingVehicle = context.vehicle
        do {
            try await db.writeAsync { db in
                var vehicle = existingVehicle ?? Vehicle(number: "")
                vehicle.number = formNumber
                vehicle.ownership = formOwnership
                vehicle.capacityKg = formCapacityKg
                vehicle.driverName = formDriverName
                vehicle.driverPhone = formDriverPhone
                vehicle.isActive = formIsActive
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