import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let toggleClipboard = Self(
        "toggleClipboard",
        default: .init(.w, modifiers: [.option])
    )
    static let paletteActions = Self(
        "paletteActions",
        default: .init(.k, modifiers: [.command])
    )
    static let paletteCopyToClipboard = Self(
        "paletteCopyToClipboard",
        default: .init(.return, modifiers: [.command])
    )
    static let palettePinToScreen = Self("palettePinToScreen")
    static let paletteTogglePin = Self(
        "paletteTogglePin",
        default: .init(.p, modifiers: [.command])
    )
    static let paletteShowInFinder = Self("paletteShowInFinder")
}

enum PaletteShortcut {
    case actions
    case copyToClipboard
    case pinToScreen
    case togglePin
    case showInFinder

    private static let actionsName = local(.paletteActions)
    private static let copyToClipboardName = local(.paletteCopyToClipboard)
    private static let pinToScreenName = local(.palettePinToScreen)
    private static let togglePinName = local(.paletteTogglePin)
    private static let showInFinderName = local(.paletteShowInFinder)

    var name: KeyboardShortcuts.Name {
        switch self {
        case .actions: Self.actionsName
        case .copyToClipboard: Self.copyToClipboardName
        case .pinToScreen: Self.pinToScreenName
        case .togglePin: Self.togglePinName
        case .showInFinder: Self.showInFinderName
        }
    }

    var shortcut: KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: name)
    }

    @MainActor
    var displayString: String? {
        shortcut?.description.replacingOccurrences(of: "↩", with: "↵")
    }

    func matches(_ eventShortcut: KeyboardShortcuts.Shortcut?) -> Bool {
        guard let eventShortcut, let shortcut else { return false }
        return eventShortcut == shortcut
    }

    func keepLocal() {
        KeyboardShortcuts.disable(name)
    }

    private static func local(
        _ name: KeyboardShortcuts.Name
    ) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.disable(name)
        return name
    }
}

private struct PaletteShortcutRecorder: View {
    let shortcut: PaletteShortcut

    var body: some View {
        KeyboardShortcuts.Recorder(for: shortcut.name) { _ in
            shortcut.keepLocal()
        }
        .onAppear {
            shortcut.keepLocal()
        }
    }
}

struct ShortcutsSettingsView: View {
    var body: some View {
        PreferencesForm {
            PreferencesRow(label: "Show Paste") {
                KeyboardShortcuts.Recorder(for: .toggleClipboard)
            }

            PreferencesDivider()

            shortcutRow("Actions", shortcut: .actions)
            shortcutRow("Copy to Clipboard", shortcut: .copyToClipboard)
            shortcutRow("Pin to Screen", shortcut: .pinToScreen)
            shortcutRow("Pin Entry", shortcut: .togglePin)
            shortcutRow("Show in Finder", shortcut: .showInFinder)
        }
    }

    private func shortcutRow(
        _ label: LocalizedStringKey,
        shortcut: PaletteShortcut
    ) -> some View {
        PreferencesRow(label: label) {
            PaletteShortcutRecorder(shortcut: shortcut)
        }
    }
}
