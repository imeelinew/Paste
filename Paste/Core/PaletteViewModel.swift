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
    /// Space toggles an overflow image Quick Look when the current selection is an image.
    @Published var imageQuickLookOpen = false
    /// Maintained by the palette view from the selected clip's kind (and menu state).
    var imageQuickLookAvailable = false

    var menuOpen = false { didSet { onMenuOpenChanged?(menuOpen) } }
    var onMenuOpenChanged: ((Bool) -> Void)?

    private var isQueryEmpty: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func requestAppMenuShortcut(_ shortcut: AppMenuShortcut) {
        appMenuShortcutRequest = AppMenuShortcutRequest(id: UUID(), shortcut: shortcut)
    }

    /// Space for `PalettePanel`: when the search field is empty, never type a leading space;
    /// if the selection is an image, toggle Quick Look instead.
    @discardableResult
    func handleSpaceKey() -> Bool {
        guard !menuOpen, isQueryEmpty else { return false }
        if imageQuickLookAvailable {
            imageQuickLookOpen.toggle()
        }
        return true
    }

    /// ⌘⌫ clears the search field (Finder-style), rather than deleting a clip.
    @discardableResult
    func clearQueryWithShortcut() -> Bool {
        guard !menuOpen else { return false }
        guard !isQueryEmpty else { return true }
        query = ""
        return true
    }

    func prepare() {
        query = ""
        selection = 0
        menuOpen = false
        appMenuShortcutRequest = nil
        imageQuickLookOpen = false
        imageQuickLookAvailable = false
        focusToken = UUID()
        resetToken = UUID()
    }
}
