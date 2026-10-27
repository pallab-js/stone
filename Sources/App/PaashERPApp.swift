import SwiftUI
import AppKit

@main
struct PaashERPApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(appState.dataEpoch)
                .environment(appState)
                .environment(\.appDatabase, appState.database)
                .tint(DS.Color.accent)
                .frame(minWidth: 1120, minHeight: 700)
                .onAppear {
                    // Prevent initial focus ring on windows
                    if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                        window.makeFirstResponder(nil)
                    }
                }
        }
        .defaultSize(width: 1360, height: 840)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            ToolbarCommands()
        }
        Settings {
            SettingsView()
                .id(appState.dataEpoch)
                .environment(appState)
                .environment(\.appDatabase, appState.database)
                .frame(minWidth: 520, idealWidth: 560)
        }
    }
}