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

    var pasteTitle: String { "Paste to \(name)" }
}

@MainActor
final class PaletteViewModel: ObservableObject {
    @Published var query = ""
    @Published var selection = 0
    @Published var focusToken = UUID()
    @Published var resetToken = UUID()
    @Published var followToken = UUID()
    @Published var pasteTarget: PasteTarget?

    var hoverHighlightArmed = false
    var menuOpen = false { didSet { onMenuOpenChanged?(menuOpen) } }
    var onMenuOpenChanged: ((Bool) -> Void)?

    func prepare() {
        query = ""
        selection = 0
        hoverHighlightArmed = false
        menuOpen = false
        focusToken = UUID()
        resetToken = UUID()
    }
}
