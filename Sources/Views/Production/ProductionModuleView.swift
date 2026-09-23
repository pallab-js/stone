import SwiftUI
import GRDB

struct ProductionBatchRow: Identifiable, Equatable {
    var id: Int64 { batch.id ?? 0 }
    var batch: ProductionBatch
    var tonnesKg: Int64
    var lineCount: Int
}

struct ProductionModuleView: View {
    @Environment(\.appDatabase) private var db
    @State private var rows: [ProductionBatchRow] = []
    @State private var selection: Int64?
    @State private var editor: ProductionEditorContext?
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var monthProductionKg: Int64 = 0
    @State private var monthDieselLitres: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            PageHeader(
                title: "Production",
                subtitle: "Crushing batches recorded per shift — every entry feeds stock automatically."
            )

            HStack(spacing: DS.Spacing.m) {
                KPIValueCard(
                    title: "This month's output",
                    value: Format.tonnesLabel(monthProductionKg),
                    icon: "gearshape.2.fill",
                    tint: DS.Color.info
                )
                KPIValueCard(
                    title: "This month's diesel",
                    value: String(format: "%.0f L", monthDieselLitres),
                    icon: "fuelpump.fill",
                    tint: DS.Color.warning
                )
            }

            if rows.isEmpty {
                EmptyStateView(
                    icon: "gearshape.2",
                    title: "No production recorded yet",
                    message: "Record a shift — date, shift, machine hours, diesel used and what got crushed. Stock updates in the same step."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
            }
        }
        .padding(DS.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.contentBackground)
        .navigationTitle("Production")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    editor = ProductionEditorContext(batch: nil)
                } label: {
                    Label("Record Shift", systemImage: "plus")
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
            ProductionEditorView(context: context) { reload() }
        }
        .destructiveConfirmation(
            title: "Delete this production batch?",
            message: "Its output will be removed from stock.",
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
        Table(of: ProductionBatchRow.self, selection: $selection) {
            TableColumn("Date") { row in
                Text(Format.day(row.batch.date))
            }
            .width(min: 110, ideal: 130)
            TableColumn("Shift") { row in
                Badge(text: "Shift \(row.batch.shift)", tint: DS.Color.info)
            }
            .width(min: 80, ideal: 90)
            TableColumn("Hours") { row in
                Text(row.batch.machineHours.map { String(format: "%.1f", $0) } ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 72)
            TableColumn("Diesel") { row in
                Text(row.batch.dieselLitres.map { String(format: "%.0f L", $0) } ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 96)
            TableColumn("Output") { row in
                Text(Format.tonnesLabel(row.tonnesKg))
                    .font(DS.Font.tableValue)
            }
            .width(min: 90, ideal: 110)
            TableColumn("Lines") { row in
                Text("\(row.lineCount) products")
                    .font(DS.Font.footnote)
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 104)
            TableColumn("Operator") { row in
                Text(row.batch.operatorName ?? "—")
                    .font(DS.Font.footnote)
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 130)
            TableColumn("Notes") { row in
                Text(row.batch.notes ?? "")
                    .font(DS.Font.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } rows: {
            ForEach(rows) { (row: ProductionBatchRow) in
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

    private var selectedRow: ProductionBatchRow? {
        guard let selection else { return nil }
        return rows.first { $0.id == selection }
    }

    private func startEditing(_ row: ProductionBatchRow) {
        editor = ProductionEditorContext(batch: row.batch)
    }

    private func rowContextMenu(_ row: ProductionBatchRow) -> some View {
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
              let batchID = rows.first(where: { $0.id == id })?.batch.id else { return }
        do {
            try db.dbQueue.write { db in
                try StockMovement
                    .filter(Column("type") == StockMovement.MoveType.production.rawValue)
                    .filter(Column("refId") == batchID)
                    .deleteAll(db)
                try ProductionItem.filter(Column("batchId") == batchID).deleteAll(db)
                try ProductionBatch.deleteOne(db, key: batchID)
            }
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() {
        do {
            let (batchRows, sumKg, sumDiesel) = try db.dbQueue.read { db -> ([ProductionBatchRow], Int64, Double) in
                let batches = try ProductionBatch.order(Column("date").desc, Column("id").desc).fetchAll(db)
                let items = try ProductionItem.fetchAll(db)
                var totals: [Int64: Int64] = [:]
                var counts: [Int64: Int] = [:]
                for item in items {
                    totals[item.batchId, default: 0] += item.qtyKg
                    counts[item.batchId, default: 0] += 1
                }
                let rows = batches.map { batch in
                    ProductionBatchRow(
                        batch: batch,
                        tonnesKg: totals[batch.id ?? 0] ?? 0,
                        lineCount: counts[batch.id ?? 0] ?? 0
                    )
                }

                let calendar = Calendar.current
                let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now
                let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? .now

                let sumKg = try Int64.fetchOne(
                    db,
                    sql: "SELECT COALESCE(SUM(qtyKg), 0) FROM stockMovements WHERE type = ? AND date >= ? AND date < ?",
                    arguments: [StockMovement.MoveType.production.rawValue, monthStart, monthEnd]
                ) ?? 0
                let sumDiesel = try Double.fetchOne(
                    db,
                    sql: "SELECT COALESCE(SUM(dieselLitres), 0) FROM productionBatches WHERE date >= ? AND date < ?",
                    arguments: [monthStart, monthEnd]
                ) ?? 0
                return (rows, sumKg, sumDiesel)
            }
            rows = batchRows
            monthProductionKg = sumKg
            monthDieselLitres = sumDiesel
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ProductionEditorContext: Identifiable {
    let id = UUID()
    let batch: ProductionBatch?
}

struct ProductionLineDraft: Identifiable {
    let id = UUID()
    var productId: Int64?
    var tonnesText = ""
    var qtyKg: Int64 {
        let tonnes = Double(tonnesText.replacingOccurrences(of: ",", with: ".")) ?? 0
        return Int64((tonnes * 1000).rounded())
    }
}

struct ProductionEditorView: View {
    @Environment(\.appDatabase) private var db
    @Environment(\.dismiss) private var dismiss
    let context: ProductionEditorContext
    let onSave: () -> Void

    @State private var date: Date
    @State private var shift: String
    @State private var hoursText: String
    @State private var dieselText: String
    @State private var operatorName: String
    @State private var notes: String
    @State private var lines: [ProductionLineDraft]
    @State private var products: [Product] = []
    @State private var errorMessage: String?

    init(context: ProductionEditorContext, onSave: @escaping () -> Void) {
        self.context = context
        self.onSave = onSave
        let batch = context.batch ?? ProductionBatch(date: .now)
        _date = State(initialValue: batch.date)
        _shift = State(initialValue: batch.shift)
        _hoursText = State(initialValue: batch.machineHours.map { String(format: "%.1f", $0) } ?? "")
        _dieselText = State(initialValue: batch.dieselLitres.map { String(format: "%.0f", $0) } ?? "")
        _operatorName = State(initialValue: batch.operatorName ?? "")
        _notes = State(initialValue: batch.notes ?? "")
        _lines = State(initialValue: [])
    }

    private var canSave: Bool {
        lines.contains { $0.qtyKg > 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(context.batch == nil ? "Record Production" : "Edit Production Batch")
                .font(DS.Font.sectionTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .horizontal], DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.s)

            Form {
                Section("Shift") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Shift", selection: $shift) {
                        Text("A").tag("A")
                        Text("B").tag("B")
                        Text("C").tag("C")
                    }
                    .pickerStyle(.segmented)
                    TextField("Machine hours (e.g. 8.5)", text: $hoursText)
                    TextField("Diesel litres", text: $dieselText)
                    TextField("Operator name", text: $operatorName)
                }

                Section("Output (tonnes)") {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                            Picker("Product", selection: lineProductBinding(index)) {
                                Text("Select product").tag(Int64?.none)
                                ForEach(products) { product in
                                    Text(product.name).tag(Int64?(product.id ?? 0))
                                }
                            }
                            TextField("Tonnes", text: lineTonnesBinding(index))
                                .frame(width: 110)
                                .multilineTextAlignment(.trailing)
                            Button {
                                removeLine(id: line.id)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(DS.Color.danger)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                    Button {
                        addLine()
                    } label: {
                        Label("Add product line", systemImage: "plus")
                    }
                    if lines.isEmpty {
                        Text("Add at least one product with the quantity crushed.")
                            .font(DS.Font.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
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
        .task {
            loadProducts()
        }
    }

    private func lineProductBinding(_ index: Int) -> Binding<Int64?> {
        Binding(
            get: { lines[index].productId },
            set: { lines[index].productId = $0 }
        )
    }

    private func lineTonnesBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { lines[index].tonnesText },
            set: { lines[index].tonnesText = $0 }
        )
    }

    private func addLine() {
        let used = Set(lines.compactMap(\.productId))
        let next = products.first { !used.contains($0.id ?? 0) }
        lines.append(ProductionLineDraft(productId: next?.id))
    }

    private func removeLine(id: UUID) {
        lines.removeAll { $0.id == id }
    }

    private func loadProducts() {
        do {
            products = try db.dbQueue.read { db in
                try Product.filter(Column("isActive") == true)
                    .order(Column("sortOrder"), Column("name"))
                    .fetchAll(db)
            }
            if context.batch != nil {
                if let batchID = context.batch?.id {
                    let items = try db.dbQueue.read { db in
                        try ProductionItem.filter(Column("batchId") == batchID).fetchAll(db)
                    }
                    for item in items {
                        lines.append(
                            ProductionLineDraft(
                                productId: item.productId,
                                tonnesText: String(format: "%.3f", Double(item.qtyKg) / 1000)
                            )
                        )
                    }
                }
            } else if lines.isEmpty, let first = products.first {
                lines.append(ProductionLineDraft(productId: first.id))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard let batchID = saveBatch() else { return }
        onSave()
        dismiss()
    }

    private func saveBatch() -> Int64? {
        let machineHours = Double(hoursText.replacingOccurrences(of: ",", with: "."))
        let dieselLitres = Double(dieselText.replacingOccurrences(of: ",", with: "."))
        do {
            var savedID: Int64?
            try db.dbQueue.write { db in
                var batch = context.batch ?? ProductionBatch(date: date)
                batch.date = date
                batch.shift = shift
                batch.machineHours = machineHours
                batch.dieselLitres = dieselLitres
                batch.operatorName = trimmedNil(operatorName)
                batch.notes = trimmedNil(notes)
                batch.updatedAt = .now
                if batch.createdAt == .distantPast { batch.createdAt = .now }
                try batch.save(db)
                guard let id = batch.id else { return }
                savedID = id

                try StockMovement
                    .filter(Column("type") == StockMovement.MoveType.production.rawValue)
                    .filter(Column("refId") == id)
                    .deleteAll(db)
                try ProductionItem.filter(Column("batchId") == id).deleteAll(db)

                for line in lines where line.qtyKg > 0 {
                    guard let productID = line.productId else { continue }
                    var item = ProductionItem(batchId: id, productId: productID, qtyKg: line.qtyKg)
                    try item.insert(db)
                    var move = StockMovement(
                        productId: productID,
                        date: date,
                        type: .production,
                        qtyKg: line.qtyKg,
                        refId: id
                    )
                    try move.insert(db)
                }
            }
            return savedID
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func trimmedNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}