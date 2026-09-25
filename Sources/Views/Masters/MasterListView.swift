import SwiftUI
import GRDB

/// Shared chrome for master-data CRUD lists (Customers, Suppliers, Products,
/// Vehicles): search field, empty state, add/edit/delete toolbar with keyboard
/// shortcuts, delete confirmation, editor sheet, error alert and a reload on
/// appear. Only the table columns and the editor sheet are app-specific.
struct MasterListView<
    RowModel: Identifiable & Equatable,
    EditorContext: Identifiable,
    EditorView: View,
    ListTable: View
>: View where RowModel.ID == Int64 {
    @Environment(\.appDatabase) private var db

    let rows: [RowModel]
    let navigationTitle: String
    let searchPrompt: String
    let addLabel: String
    let emptyIcon: String
    let emptyTitle: String
    let emptyMessage: String
    let deleteConfirmationTitle: String
    let deleteConfirmationMessage: String

    var filter: (RowModel, String) -> Bool
    var deactivationMessage: (RowModel) -> String
    var makeNewContext: () -> EditorContext
    var makeEditContext: (RowModel) -> EditorContext
    var editorSheet: (EditorContext, @escaping () -> Void) -> EditorView
    var deleteEntity: @Sendable (Database, Int64) throws -> MasterDeletion.Outcome
    var table: (Binding<Int64?>, [RowModel], @escaping (RowModel) -> Void, @escaping (RowModel) -> Void) -> ListTable
    /// Async so `.task` can await the first load before dismissing the loading
    /// overlay — a synchronous `() -> Void` returning a detached `Task` would
    /// let `loaded = true` run before any row is fetched.
    var onReload: () async -> Void

    @State private var search = ""
    @State private var selection: Int64?
    @State private var editor: EditorContext?
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var loaded = false

    private var filteredRows: [RowModel] {
        guard !search.isEmpty else { return rows }
        return rows.filter { filter($0, search) }
    }

    var body: some View {
        Group {
            if filteredRows.isEmpty {
                EmptyStateView(
                    icon: emptyIcon,
                    title: search.isEmpty ? emptyTitle : "No matches for “\(search)”",
                    message: search.isEmpty ? emptyMessage : "Nothing matches your search. Try a different name, code or keyword."
                )
            } else {
                table($selection, filteredRows, startEditing, deleteRow)
            }
        }
        .padding(DS.Spacing.xl)
        .frame(maxWidth: 1280)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.contentBackground)
        .loadingOverlay(!loaded)
        .searchable(text: $search, placement: .toolbar, prompt: searchPrompt)
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    editor = makeNewContext()
                } label: {
                    Label(addLabel, systemImage: "plus")
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
            editorSheet(context, { Task { await onReload() } })
        }
        .destructiveConfirmation(
            title: deleteConfirmationTitle,
            message: deleteConfirmationMessage,
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
        .task { await onReload(); loaded = true }
    }

    private var selectedRow: RowModel? {
        guard let selection else { return nil }
        return rows.first { $0.id == selection }
    }

    private func startEditing(_ row: RowModel) {
        editor = makeEditContext(row)
    }

    private func deleteRow(_ row: RowModel) {
        selection = row.id
        confirmDelete = true
    }

    private func deleteSelected() async {
        guard let id = selection, let row = rows.first(where: { $0.id == id }) else { return }
        let delete = deleteEntity
        do {
            let outcome = try await db.writeAsync { db in
                try delete(db, id)
            }
            if outcome == .deactivated {
                errorMessage = deactivationMessage(row)
            }
            await onReload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}