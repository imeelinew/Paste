import Foundation

/// Controls Spotlight's macOS 26+ clipboard-history preference. The shared pasteboard itself
/// must remain running because Paste and every app's Copy/Paste commands depend on it.
@MainActor
final class SystemClipboardHistory: ObservableObject {
    private static let preferenceDomain = "com.apple.Spotlight"
    private static let enabledKey = "PasteboardHistoryEnabled"

    private let defaults: UserDefaults?

    @Published private(set) var isDisabled: Bool

    init() {
        let defaults = UserDefaults(suiteName: Self.preferenceDomain)
        self.defaults = defaults
        if let defaults {
            isDisabled = !defaults.bool(forKey: Self.enabledKey)
        } else {
            isDisabled = false
            NSLog("Paste: could not open the Spotlight preferences domain")
        }
    }

    func setDisabled(_ disabled: Bool) {
        guard let defaults else { return }
        defaults.set(!disabled, forKey: Self.enabledKey)
        guard defaults.synchronize() else {
            refresh()
            return
        }
        refresh()
    }

    func refresh() {
        guard let defaults else { return }
        defaults.synchronize()
        isDisabled = !defaults.bool(forKey: Self.enabledKey)
    }
}
