import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let toggleClipboard = Self(
        "toggleClipboard",
        default: .init(.w, modifiers: [.option])
    )
}

struct ShortcutRecorder: View {
    var body: some View {
        KeyboardShortcuts.Recorder(for: .toggleClipboard)
    }
}
