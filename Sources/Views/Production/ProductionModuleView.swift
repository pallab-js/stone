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
    @State private var searchText = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            PageHeader(
                title: "Production",
                subtitle: "Crushing batches recorded per shift — every entry feeds stock automatically."
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 215), spacing: DS.Spacing.m, alignment: .top)],
                spacing: DS.Spacing.m
            ) {
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
            } else if filteredRows.isEmpty {
                InlineEmptyState(
                    icon: "magnifyingglass",
                    title: "No matching batches",
                    message: "Nothing matches “\(searchText)”. Try date, operator, shift or notes."
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
        .navigationTitle("Production")
        .loadingOverlay(!loaded)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search shift, operator or notes")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    editor = ProductionEditorContext(batch: nil)
                } label: {
                    Label("Record Shift", systemImage: "plus")
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
            ProductionEditorView(context: context) { Task { await reload() } }
        }
        .destructiveConfirmation(
            title: "Delete this production batch?",
            message: "Its output will be removed from stock.",
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
            ForEach(filteredRows) { (row: ProductionBatchRow) in
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

    private var filteredRows: [ProductionBatchRow] {
        guard !searchText.isEmpty else { return rows }
        let query = searchText.trimmingCharacters(in: .whitespaces).localizedLowercase
        return rows.filter { row in
            "Shift \(row.batch.shift)".localizedLowercase.contains(query)
                || (row.batch.operatorName?.localizedLowercase.contains(query) ?? false)
                || (row.batch.notes?.localizedLowercase.contains(query) ?? false)
                || Format.day(row.batch.date).localizedLowercase.contains(query)
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

    private func deleteSelected() async {
        guard let id = selection,
              let batchID = rows.first(where: { $0.id == id })?.batch.id else { return }
        do {
            try await db.writeAsync { db in
                // Deleting a batch removes its production credits; block if the
                // output has since been consumed and the ledger would go negative.
                // The gate sums duplicate products for us — per-line checks would
                // only prove the balance covers each line, not their total.
                let items = try ProductionItem.filter(Column("batchId") == batchID).fetchAll(db)
                try StockGate.requireForRemoval(
                    db: db,
                    removing: items.map { (productID: $0.productId, qtyKg: $0.qtyKg) },
                    productName: { pid in try? Product.fetchOne(db, key: pid)?.name }
                )
                try StockMovement
                    .filter(Column("type") == StockMovement.MoveType.production.rawValue)
                    .filter(Column("refId") == batchID)
                    .deleteAll(db)
                try ProductionItem.filter(Column("batchId") == batchID).deleteAll(db)
                try ProductionBatch.deleteOne(db, key: batchID)
            }
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() async {
        do {
            let (batchRows, sumKg, sumDiesel) = try await db.readAsync { db -> ([ProductionBatchRow], Int64, Double) in
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
        Format.kg(fromTonnes: tonnesText)
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
        // Round-trip the stored precision (%.2f), not a display rounding:
        // 8.55 machine hours or 30.5 diesel litres would otherwise be rewritten
        // as 8.6 / 30 on the next save.
        _hoursText = State(initialValue: batch.machineHours.map { String(format: "%.2f", $0) } ?? "")
        _dieselText = State(initialValue: batch.dieselLitres.map { String(format: "%.2f", $0) } ?? "")
        _operatorName = State(initialValue: batch.operatorName ?? "")
        _notes = State(initialValue: batch.notes ?? "")
        _lines = State(initialValue: [])
    }

    private var canSave: Bool {
        // A line with a quantity but no product would be skipped on save
        // (`guard let productID = line.productId else { continue }`), silently
        // dropping the production output, so require a complete line and reject
        // any half-finished one.
        guard lines.contains(where: { $0.productId != nil && $0.qtyKg > 0 }) else { return false }
        return !lines.contains { $0.productId == nil && $0.qtyKg > 0 }
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
                    ForEach(lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                            Picker("Product", selection: lineProductBinding(line.id)) {
                                Text("Select product").tag(Int64?.none)
                                ForEach(products) { product in
                                    Text(product.name).tag(Int64?(product.id ?? 0))
                                }
                            }
                            TextField("Tonnes", text: lineTonnesBinding(line.id))
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
                Button("Save") { Task { await save() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(DS.Spacing.lg)
        }
        .frame(width: DS.SheetWidth.editor)
        .padding(.top, DS.Spacing.s)
        .task {
            await loadProducts()
        }
    }

    // Keyed by line id, not position: a captured index can point past the end
    // of `lines` once a line is removed or the array is replaced by a load
    // finishing, trapping on the still-focused field.
    private func lineProductBinding(_ id: UUID) -> Binding<Int64?> {
        Binding(
            get: { lines.first(where: { $0.id == id })?.productId },
            set: { newValue in
                guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
                lines[index].productId = newValue
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

    private func addLine() {
        let used = Set(lines.compactMap(\.productId))
        let next = products.first { $0.isActive && !used.contains($0.id ?? 0) }
        lines.append(ProductionLineDraft(productId: next?.id))
    }

    private func removeLine(id: UUID) {
        lines.removeAll { $0.id == id }
    }

    private func loadProducts() async {
        do {
            let all = try await db.readAsync { db in
                try Product.order(Column("sortOrder"), Column("name")).fetchAll(db)
            }
            products = all.filter(\.isActive)
            if context.batch != nil {
                if let batchID = context.batch?.id {
                    let items = try await db.readAsync { db in
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
                    // A deactivated product still on this batch must remain
                    // selectable, otherwise the picker renders blank for it.
                    let activeIDs = Set(products.compactMap(\.id))
                    let referenced = Set(lines.compactMap(\.productId)).subtracting(activeIDs)
                    if !referenced.isEmpty {
                        products += all.filter { referenced.contains($0.id ?? 0) }
                    }
                }
            } else if lines.isEmpty, let first = products.first {
                lines.append(ProductionLineDraft(productId: first.id))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        guard let batchID = await saveBatch() else { return }
        onSave()
        dismiss()
    }

    private func saveBatch() async -> Int64? {
        let machineHours = Format.parse(hoursText)
        let dieselLitres = Format.parse(dieselText)
        let formLines = lines
        let formDate = date
        let formShift = shift
        let formHours = machineHours
        let formDiesel = dieselLitres
        let formOperator = trimmedNil(operatorName)
        let formNotes = trimmedNil(notes)
        let existingBatch = context.batch
        do {
            let savedID = try await db.writeAsync { db -> Int64? in
                var batch = existingBatch ?? ProductionBatch(date: formDate)
                batch.date = formDate
                batch.shift = formShift
                batch.machineHours = formHours
                batch.dieselLitres = formDiesel
                batch.operatorName = formOperator
                batch.notes = formNotes
                batch.updatedAt = .now
                if batch.createdAt == .distantPast { batch.createdAt = .now }
                try batch.save(db)
                guard let id = batch.id else { return nil }

                // Shrinking an edited batch removes production credits that may
                // already have been consumed by sales; block if the ledger would
                // go negative for any product.
                let oldItems = try ProductionItem.filter(Column("batchId") == id).fetchAll(db)
                var newByProduct: [Int64: Int64] = [:]
                for line in formLines where line.qtyKg > 0 {
                    if let productID = line.productId {
                        newByProduct[productID, default: 0] += line.qtyKg
                    }
                }
                // The gate compares per-product *totals* (old vs new), so a batch
                // holding several lines for one product can't slip past it.
                try StockGate.requireForRemoval(
                    db: db,
                    reducing: oldItems.map { (productID: $0.productId, qtyKg: $0.qtyKg) },
                    to: newByProduct,
                    productName: { pid in try? Product.fetchOne(db, key: pid)?.name }
                )
                try StockMovement
                    .filter(Column("type") == StockMovement.MoveType.production.rawValue)
                    .filter(Column("refId") == id)
                    .deleteAll(db)
                try ProductionItem.filter(Column("batchId") == id).deleteAll(db)

                for line in formLines where line.qtyKg > 0 {
                    guard let productID = line.productId else { continue }
                    var item = ProductionItem(batchId: id, productId: productID, qtyKg: line.qtyKg)
                    try item.insert(db)
                    var move = StockMovement(
                        productId: productID,
                        date: formDate,
                        type: .production,
                        qtyKg: line.qtyKg,
                        refId: id
                    )
                    try move.insert(db)
                }
                return id
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