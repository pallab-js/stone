import SwiftUI
import GRDB

struct PurchaseRow: Identifiable, Equatable {
    var id: Int64 { purchase.id ?? 0 }
    var purchase: Purchase
    var supplierName: String?
}

struct PurchasesModuleView: View {
    @Environment(\.appDatabase) private var db
    @State private var rows: [PurchaseRow] = []
    @State private var selection: Int64?
    @State private var editor: PurchaseEditorContext?
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var monthExpensePaise: Int64 = 0
    @State private var searchText = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            PageHeader(
                title: "Purchases & Expenses",
                subtitle: "Diesel, electricity, quarry royalty, spare parts, labour, rent."
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 215), spacing: DS.Spacing.m, alignment: .top)],
                spacing: DS.Spacing.m
            ) {
                KPIValueCard(
                    title: "This month's spend",
                    value: Format.inr(monthExpensePaise),
                    icon: "cart.fill",
                    tint: DS.Color.warning
                )
            }

            if rows.isEmpty {
                EmptyStateView(
                    icon: "cart",
                    title: "No expenses recorded",
                    message: "Record every diesel purchase, electricity bill, royalty payment or parts purchase. Categories feed the dashboard and reports."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredRows.isEmpty {
                InlineEmptyState(
                    icon: "magnifyingglass",
                    title: "No matching expenses",
                    message: "Nothing matches “\(searchText)”. Try category, supplier, detail or mode."
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
        .navigationTitle("Purchases & Expenses")
        .loadingOverlay(!loaded)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search category, supplier or detail")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    editor = PurchaseEditorContext(purchase: nil)
                } label: {
                    Label("Record Expense", systemImage: "plus")
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
            PurchaseEditorView(context: context) { Task { await reload() } }
        }
        .destructiveConfirmation(
            title: "Delete this expense?",
            message: "It will be removed from the expense records and totals.",
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
        Table(of: PurchaseRow.self, selection: $selection) {
            TableColumn("Date") { row in
                Text(Format.day(row.purchase.date))
            }
            .width(min: 110, ideal: 130)
            TableColumn("Category") { row in
                Badge(text: row.purchase.category.label, tint: DS.Color.info)
            }
            .width(min: 110, ideal: 130)
            TableColumn("Supplier") { row in
                Text(row.supplierName ?? "—")
                    .font(DS.Font.footnote)
                    .foregroundStyle(.secondary)
            }
            TableColumn("Detail") { row in
                Text(detailText(row.purchase))
                    .font(DS.Font.footnote)
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150)
            TableColumn("Mode") { row in
                Text(row.purchase.mode.label)
                    .font(DS.Font.footnote)
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110)
            TableColumn("Amount") { row in
                Text(Format.inr(row.purchase.amountPaise))
                    .font(DS.Font.tableValue)
            }
            .width(min: 110, ideal: 130)
        } rows: {
            ForEach(filteredRows) { (row: PurchaseRow) in
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

    private func detailText(_ purchase: Purchase) -> String {
        if purchase.category == .diesel, let litres = purchase.qtyLitres, let rate = purchase.ratePaise {
            return String(format: "%.0f L × ₹%.2f", litres, Double(rate) / 100)
        }
        return purchase.notes ?? ""
    }

    private var filteredRows: [PurchaseRow] {
        guard !searchText.isEmpty else { return rows }
        let query = searchText.trimmingCharacters(in: .whitespaces).localizedLowercase
        return rows.filter { row in
            row.purchase.category.label.localizedLowercase.contains(query)
                || (row.supplierName?.localizedLowercase.contains(query) ?? false)
                || detailText(row.purchase).localizedLowercase.contains(query)
                || row.purchase.mode.label.localizedLowercase.contains(query)
        }
    }

    private var selectedRow: PurchaseRow? {
        guard let selection else { return nil }
        return rows.first { $0.id == selection }
    }

    private func startEditing(_ row: PurchaseRow) {
        editor = PurchaseEditorContext(purchase: row.purchase)
    }

    private func rowContextMenu(_ row: PurchaseRow) -> some View {
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
              let purchaseID = rows.first(where: { $0.id == id })?.purchase.id else { return }
        do {
            try await db.writeAsync { db in
                try Purchase.deleteOne(db, key: purchaseID)
            }
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() async {
        do {
            let result = try await db.readAsync { db -> ([PurchaseRow], Int64) in
                let purchases = try Purchase.order(Column("date").desc, Column("id").desc).fetchAll(db)
                let suppliers = try Supplier.fetchAll(db)
                var supplierName = [Int64: String]()
                for supplier in suppliers {
                    if let id = supplier.id { supplierName[id] = supplier.name }
                }
                let rows = purchases.map { purchase in
                    PurchaseRow(
                        purchase: purchase,
                        supplierName: purchase.supplierId.flatMap { supplierName[$0] }
                    )
                }
                let calendar = Calendar.current
                let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now
                let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? .now
                let total = try Int64.fetchOne(
                    db,
                    sql: "SELECT COALESCE(SUM(amountPaise), 0) FROM purchases WHERE date >= ? AND date < ?",
                    arguments: [monthStart, monthEnd]
                ) ?? 0
                return (rows, total)
            }
            rows = result.0
            monthExpensePaise = result.1
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PurchaseEditorContext: Identifiable {
    let id = UUID()
    let purchase: Purchase?
}

struct PurchaseEditorView: View {
    @Environment(\.appDatabase) private var db
    @Environment(\.dismiss) private var dismiss
    let context: PurchaseEditorContext
    let onSave: () -> Void

    @State private var date: Date
    @State private var category: Purchase.Category
    @State private var supplierId: Int64?
    @State private var amountText: String
    @State private var mode: Payment.Mode
    @State private var qtyLitresText = ""
    @State private var rateText = ""
    @State private var notes: String
    @State private var suppliers: [Supplier] = []
    @State private var errorMessage: String?

    init(context: PurchaseEditorContext, onSave: @escaping () -> Void) {
        self.context = context
        self.onSave = onSave
        let purchase = context.purchase ?? Purchase(date: .now, category: .diesel, amountPaise: 0)
        _date = State(initialValue: purchase.date)
        _category = State(initialValue: purchase.category)
        _supplierId = State(initialValue: purchase.supplierId)
        _amountText = State(initialValue: String(format: "%.2f", Double(purchase.amountPaise) / 100))
        _mode = State(initialValue: purchase.mode)
        _qtyLitresText = State(initialValue: purchase.qtyLitres.map { String(format: "%.0f", $0) } ?? "")
        _rateText = State(initialValue: purchase.ratePaise.map { String(format: "%.2f", Double($0) / 100) } ?? "")
        _notes = State(initialValue: purchase.notes ?? "")
    }

    private var amountPaise: Int64 {
        Format.paise(amountText)
    }

    private var canSave: Bool {
        amountPaise > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(context.purchase == nil ? "Record Expense" : "Edit Expense")
                .font(DS.Font.sectionTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .horizontal], DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.s)

            Form {
                Section("Expense") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Category", selection: $category) {
                        ForEach(Purchase.Category.allCases) { category in
                            Text(category.label).tag(category)
                        }
                    }
                    Picker("Supplier", selection: $supplierId) {
                        Text("—").tag(Int64?.none)
                        ForEach(suppliers) { supplier in
                            Text(supplier.name).tag(Int64?(supplier.id ?? 0))
                        }
                    }
                    TextField("Amount (₹)", text: $amountText)
                }

                if category == .diesel {
                    Section("Diesel detail") {
                        TextField("Litres", text: $qtyLitresText)
                        TextField("Rate per litre (₹)", text: $rateText)
                        let litres = Format.parse(qtyLitresText) ?? 0
                        let rate = Format.parse(rateText) ?? 0
                        if litres > 0, rate > 0 {
                            Button {
                                amountText = String(format: "%.2f", litres * rate)
                            } label: {
                                Label("Apply amount \(Format.rupees(litres * rate))", systemImage: "arrow.down.circle.fill")
                                    .font(DS.Font.footnote)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("Auto amount: \(Format.rupees(litres * rate))")
                                .font(DS.Font.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Picker("Payment mode", selection: $mode) {
                        ForEach(Payment.Mode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
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
        .task { await loadSuppliers() }
    }

    private func loadSuppliers() async {
        do {
            suppliers = try await db.readAsync { db in
                try Supplier.filter(Column("isActive") == true).order(Column("name")).fetchAll(db)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        let litres = Format.parse(qtyLitresText)
        let rate = Format.parse(rateText)
        let formDate = date
        let formCategory = category
        let formSupplierId = supplierId
        let formAmount = amountPaise
        let formMode = mode
        let formQtyLitres = litres
        let formRate = rate.map { Int64(($0 * 100).rounded()) }
        let formNotes = trimmedNil(notes)
        let existingPurchase = context.purchase
        do {
            try await db.writeAsync { db in
                var purchase = existingPurchase ?? Purchase(date: formDate, category: formCategory, amountPaise: formAmount)
                purchase.date = formDate
                purchase.category = formCategory
                purchase.supplierId = formSupplierId
                purchase.amountPaise = formAmount
                purchase.mode = formMode
                purchase.qtyLitres = formQtyLitres
                purchase.ratePaise = formRate
                purchase.notes = formNotes
                try purchase.save(db)
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