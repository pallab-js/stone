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
                            Button("Save profile") { saveProfile() }
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
                        Text("Take a copy of the whole database file to keep with your records. A daily snapshot is also kept locally.")
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
                            if let url = appState.databaseURL {
                                Text(url.path)
                                    .font(DS.Font.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
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
        .task { loadProfile() }
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

    private func loadProfile() {
        do {
            let profile = try db.dbQueue.read { db -> [String: String] in
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

    private func saveProfile() {
        do {
            try db.dbQueue.write { db in
                try AppSetting.set(key: "business_name", value: businessName, db: db)
                try AppSetting.set(key: "business_gstin", value: gstin, db: db)
                try AppSetting.set(key: "business_address", value: address, db: db)
                try AppSetting.set(key: "business_city", value: city, db: db)
                try AppSetting.set(key: "business_state", value: state, db: db)
            }
            dirty = false
            saved = true
        } catch {
            noticeMessage = error.localizedDescription
        }
    }

    private func clearAll() {
        do {
            try appState.resetDatabase(seed: false)
            noticeMessage = "Data cleared. Start fresh or reinstall demo data."
            loadProfile()
        } catch {
            noticeMessage = error.localizedDescription
        }
    }

    private func reseed() {
        do {
            try appState.resetDatabase(seed: true)
            noticeMessage = "Demo data reinstalled."
            loadProfile()
        } catch {
            noticeMessage = error.localizedDescription
        }
    }

    private func prepareBackup() {
        guard let url = appState.databaseURL,
              let data = try? Data(contentsOf: url) else {
            noticeMessage = "Could not read the database for backup."
            return
        }
        backupDocument = DatabaseBackupDocument(data: data)
        let stamp = Format.shortDate(.now).replacingOccurrences(of: "/", with: "-")
        backupFileName = "PaashERP-backup-\(stamp).sqlite"
        showExporter = true
    }
}