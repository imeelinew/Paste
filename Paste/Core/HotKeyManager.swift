import Carbon.HIToolbox
import Foundation

@MainActor
final class HotKeyManager: ObservableObject {
    var onToggleClipboard: (() -> Void)?

    @Published var recordingAction: HotKeyAction? {
        didSet { center.isPaused = recordingAction != nil }
    }

    private let center = HotKeyCenter()
    private let defaultSeededKey = "PasteDefaultShortcutSeeded"

    func start() {
        if !UserDefaults.standard.bool(forKey: defaultSeededKey) {
            if shortcut(for: .toggleClipboard) == nil {
                setShortcut(
                    KeyShortcut(
                        carbonKeyCode: Int(kVK_ANSI_W), carbonModifiers: Int(optionKey)),
                    for: .toggleClipboard)
            }
            UserDefaults.standard.set(true, forKey: defaultSeededKey)
        }
        register(.toggleClipboard)
    }

    func shortcut(for action: HotKeyAction) -> KeyShortcut? {
        guard
            let json = UserDefaults.standard.string(forKey: action.defaultsKey),
            let data = json.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(KeyShortcut.self, from: data)
    }

    func setShortcut(_ shortcut: KeyShortcut?, for action: HotKeyAction) {
        objectWillChange.send()
        if let shortcut,
            let data = try? JSONEncoder().encode(shortcut),
            let json = String(data: data, encoding: .utf8)
        {
            UserDefaults.standard.set(json, forKey: action.defaultsKey)
            register(action)
        } else {
            UserDefaults.standard.removeObject(forKey: action.defaultsKey)
            center.unregister(id: action.defaultsKey)
        }
    }

    func conflictOwner(of shortcut: KeyShortcut, excluding action: HotKeyAction) -> String? {
        nil
    }

    private func register(_ action: HotKeyAction) {
        guard let shortcut = shortcut(for: action) else { return }
        center.register(id: action.defaultsKey, shortcut: shortcut) { [weak self] in
            self?.onToggleClipboard?()
        }
    }
}
