import SwiftUI

@main
struct PaashERPApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(\.appDatabase, appState.database)
                .tint(DS.Color.accent)
                .frame(minWidth: 1120, minHeight: 700)
        }
        .defaultSize(width: 1360, height: 840)
        .commands {
            SidebarCommands()
        }
        Settings {
            SettingsView()
                .environment(appState)
                .environment(\.appDatabase, appState.database)
                .frame(width: 560)
        }
    }
}