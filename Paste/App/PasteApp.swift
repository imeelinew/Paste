import AppKit
import SwiftUI

@main
struct PasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true

    var body: some Scene {
        MenuBarExtra(
            "Paste", systemImage: "macwindow.on.rectangle", isInserted: $showInMenuBar
        ) {
            Button("Clipboard History") { AppCore.shared.showPalette() }
            Divider()
            Button("Settings...") { AppCore.shared.showSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit Paste") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppCore.shared.start()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        AppCore.shared.handleReopen()
        return true
    }
}
