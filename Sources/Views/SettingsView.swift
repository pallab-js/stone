import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appDatabase) private var db

    @State private var businessName = ""
    @State private var gstin = ""
    @State private var address = ""
    @State private var city = ""
    @State private var state = ""
    @State private var dirty = false

    @State private var showExporter = false
    @State private var backupDocument: DatabaseBackupDocument?
    @State private var backupFileName = "PaashERP-backup.sqlite"

    @State private var showRestoreImporter = false
    @State private var pendingRestoreURL: URL?
    @State private var confirmRestore = false
    @State private var restoreError: String?

    @State private var confirmClear = false
    @State private var confirmReseed = false
    @State private var noticeMessage: String?
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                PageHeader(title: "Settings & Backup", subtitle: "Business profile and data management — all stored locally")
                    .padding(.bottom, DS.Spacing.s)

                CardContainer {
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                        SectionHeading(title: "Business profile")
                        VStack(alignment: .leading, spacing: DS.Spacing.m) {
                            settingsField("Business name", text: $businessName)
                            settingsField("GSTIN", text: $gstin)
                            settingsField("Street address", text: $address)
                            settingsField("City", text: $city)
                            settingsField("State", text: $state)
                        }
                        HStack {
                            Spacer()
                            if saved {
                                Label("Saved", systemImage: "checkmark.circle.fill")
                                    .font(DS.Font.footnote)
                                    .foregroundStyle(DS.Color.success)
                            }
                            Button("Save profile") { Task { await saveProfile() } }
                                .buttonStyle(.borderedProminent)
                                .disabled(!dirty)
                        }
                    }
                }

                CardContainer {
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                        SectionHeading(title: "Data management")
                        Text("Everything lives in one SQLite file on this Mac. Nothing is uploaded anywhere, and the app works fully offline.")
                            .font(DS.Font.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: DS.Spacing.s) {
                            Button {
                                confirmClear = true
                            } label: {
                                Label("Clear all data", systemImage: "trash")
                                    .foregroundStyle(DS.Color.danger)
                            }
                            .destructiveConfirmation(
                                title: "Clear all data?",
                                message: "This permanently deletes products, parties, invoices, stock and settings from this Mac.",
                                destructiveLabel: "Clear everything",
                                isPresented: $confirmClear
                            ) { clearAll() }

                            Button {
                                confirmReseed = true
                            } label: {
                                Label("Reinstall demo data", systemImage: "arrow.clockwise")
                            }
                            .destructiveConfirmation(
                                title: "Replace with fresh demo data?",
                                message: "All current data is wiped and replaced with the 30-day demonstration dataset.",
                                destructiveLabel: "Reinstall demo data",
                                isPresented: $confirmReseed
                            ) { reseed() }
                        }
                    }
                }

                CardContainer {
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                        SectionHeading(title: "Backups")
                        Text("Take a consistent snapshot of the whole database to keep with your records — safe to capture even while you are working.")
                            .font(DS.Font.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button {
                                prepareBackup()
                            } label: {
                                Label("Back up database…", systemImage: "externaldrive.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(appState.databaseURL == nil)
                            Button {
                                showRestoreImporter = true
                            } label: {
                                Label("Restore backup…", systemImage: "arrow.down.doc.fill")
                            }
                            .disabled(appState.databaseURL == nil)
                            .destructiveConfirmation(
                                title: "Restore this backup?",
                                message: "All current data on this Mac is replaced by the contents of the backup. Back up the current data first if you need to keep it.",
                                destructiveLabel: "Restore backup",
                                isPresented: $confirmRestore
                            ) { restorePendingBackup() }
                            if let url = appState.databaseURL {
                                Text(url.path)
                                    .font(DS.Font.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        Text("Restoring replaces all current data with the selected backup, after validating it.")
                            .font(DS.Font.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let noticeMessage {
                    Label(noticeMessage, systemImage: "info.circle")
                        .font(DS.Font.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("PaashERP v0.1.0 · MIT License · Local-first · Offline-first")
                    .font(DS.Font.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, DS.Spacing.m)
            }
            .padding(DS.Spacing.xl)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .background(DS.Color.contentBackground)
        .navigationTitle("Settings & Backup")
        .fileExporter(
            isPresented: $showExporter,
            document: backupDocument,
            contentType: .database,
            defaultFilename: backupFileName
        ) { result in
            switch result {
            case .success:
                noticeMessage = "Backup exported successfully."
            case .failure(let error):
                noticeMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $showRestoreImporter,
            allowedContentTypes: [.database],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    try BackupRestore.validateBackup(at: url)
                    pendingRestoreURL = url
                    confirmRestore = true
                } catch {
                    restoreError = error.localizedDescription
                }
            case .failure(let error):
                restoreError = error.localizedDescription
            }
        }
        .alert("Cannot restore this backup", isPresented: Binding(
            get: { restoreError != nil },
            set: { if !$0 { restoreError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreError ?? "")
        }
        .task { await loadProfile() }
    }

    private func settingsField(_ label: String, text: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(DS.Font.body)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
        .onChange(of: text.wrappedValue) {
            dirty = true
            saved = false
        }
    }

    private func loadProfile() async {
        do {
            let profile = try await db.readAsync { db -> [String: String] in
                let keys = ["business_name", "business_gstin", "business_address", "business_city", "business_state"]
                var values: [String: String] = [:]
                for key in keys {
                    values[key] = try AppSetting.value(forKey: key, db: db)
                }
                return values
            }
            businessName = profile["business_name"] ?? ""
            gstin = profile["business_gstin"] ?? ""
            address = profile["business_address"] ?? ""
            city = profile["business_city"] ?? ""
            state = profile["business_state"] ?? ""
            dirty = false
        } catch {
            noticeMessage = error.localizedDescription
        }
    }

    private func saveProfile() async {
        let formName = businessName
        let formGstin = gstin
        let formAddress = address
        let formCity = city
        let formState = state
        do {
            try await db.writeAsync { db in
                try AppSetting.set(key: "business_name", value: formName, db: db)
                try AppSetting.set(key: "business_gstin", value: formGstin, db: db)
                try AppSetting.set(key: "business_address", value: formAddress, db: db)
                try AppSetting.set(key: "business_city", value: formCity, db: db)
                try AppSetting.set(key: "business_state", value: formState, db: db)
            }
            dirty = false
            saved = true
        } catch {
            noticeMessage = error.localizedDescription
        }
    }

    private func clearAll() {
        Task {
            do {
                try await appState.resetDatabase(seed: false)
                noticeMessage = "Data cleared. Start fresh or reinstall demo data."
                await loadProfile()
            } catch {
                noticeMessage = error.localizedDescription
            }
        }
    }

    private func reseed() {
        Task {
            do {
                try await appState.resetDatabase(seed: true)
                noticeMessage = "Demo data reinstalled."
                await loadProfile()
            } catch {
                noticeMessage = error.localizedDescription
            }
        }
    }

    private func prepareBackup() {
        guard let url = appState.databaseURL else {
            noticeMessage = "The database is not available for backup."
            return
        }
        do {
            // Snapshot into a temp file through SQLite's Online Backup API
            // (consistent even mid-write), then hand the bytes to the exporter.
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("PaashERP-backup-\(UUID().uuidString).sqlite")
            try BackupRestore.createBackup(from: db.dbQueue, to: tempURL)
            let data = try Data(contentsOf: tempURL)
            try? FileManager.default.removeItem(at: tempURL)
            backupDocument = DatabaseBackupDocument(data: data)
            let stamp = Format.shortDate(.now).replacingOccurrences(of: "/", with: "-")
            backupFileName = "PaashERP-backup-\(stamp).sqlite"
            showExporter = true
        } catch {
            noticeMessage = error.localizedDescription
        }
    }

    private func restorePendingBackup() {
        guard let url = pendingRestoreURL else { return }
        do {
            try appState.restoreBackup(from: url)
            pendingRestoreURL = nil
            noticeMessage = "Backup restored. All screens now show the restored data."
            Task { await loadProfile() }
        } catch {
            pendingRestoreURL = nil
            restoreError = error.localizedDescription
        }
    }
}