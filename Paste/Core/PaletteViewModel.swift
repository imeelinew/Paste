import AppKit
import SwiftUI

struct PasteTarget: Equatable {
    let name: String
    let iconPath: String?

    init?(app: NSRunningApplication?) {
        guard let app, let name = app.localizedName else { return nil }
        self.name = name
        iconPath = app.bundleURL?.path
    }

    var pasteTitle: LocalizedStringKey { "Paste to \(name)" }
}

/// App-menu items reached by ⌘, / ⌘Q; the palette plays the menu open → select → press choreography first.
enum AppMenuShortcut: Equatable {
    case settings
    case quit

    var itemIndex: Int {
        switch self {
        case .settings: return 1
        case .quit: return 2
        }
    }
}

struct AppMenuShortcutRequest: Equatable {
    let id: UUID
    let shortcut: AppMenuShortcut
}

@MainActor
final class PaletteViewModel: ObservableObject {
    @Published var query = ""
    @Published var selection = 0
    @Published var focusToken = UUID()
    @Published var resetToken = UUID()
    @Published var followToken = UUID()
    @Published var pasteTarget: PasteTarget?
    @Published var appMenuShortcutRequest: AppMenuShortcutRequest?

    var hoverHighlightArmed = false
    var menuOpen = false { didSet { onMenuOpenChanged?(menuOpen) } }
    var onMenuOpenChanged: ((Bool) -> Void)?

    func requestAppMenuShortcut(_ shortcut: AppMenuShortcut) {
        appMenuShortcutRequest = AppMenuShortcutRequest(id: UUID(), shortcut: shortcut)
    }

    func prepare() {
        query = ""
        selection = 0
        hoverHighlightArmed = false
        menuOpen = false
        appMenuShortcutRequest = nil
        focusToken = UUID()
        resetToken = UUID()
    }
}
