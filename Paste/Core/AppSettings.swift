import AppKit
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Follow System"
        case .english: return "English"
        case .simplifiedChinese: return "Simplified Chinese"
        }
    }

    var locale: Locale {
        switch self {
        case .system: return .autoupdatingCurrent
        case .english: return Locale(identifier: "en")
        case .simplifiedChinese: return Locale(identifier: "zh-Hans")
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Follow System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let clipboardRetention = "clipboardRetentionDays"
        static let clipboardDisabledApps = "clipboardDisabledApps"
        static let openOnCursorScreen = "openOnCursorScreen"
        static let launchAtLogin = "launchAtLogin"
        static let switchToEnglishInputOnOpen = "switchToEnglishInputOnOpen"
        static let language = "appLanguage"
        static let appearance = "appAppearance"
    }

    @Published var clipboardRetention: ClipboardRetention {
        didSet { defaults.set(clipboardRetention.rawValue, forKey: Key.clipboardRetention) }
    }

    @Published var clipboardDisabledApps: [String] {
        didSet { defaults.set(clipboardDisabledApps, forKey: Key.clipboardDisabledApps) }
    }

    @Published var openOnCursorScreen: Bool {
        didSet { defaults.set(openOnCursorScreen, forKey: Key.openOnCursorScreen) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
            LaunchAtLogin.set(launchAtLogin)
        }
    }

    /// When enabled, opening the palette selects the English keyboard so pinyin search can be typed directly.
    @Published var switchToEnglishInputOnOpen: Bool {
        didSet { defaults.set(switchToEnglishInputOnOpen, forKey: Key.switchToEnglishInputOnOpen) }
    }

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Key.language) }
    }

    @Published var appearance: AppAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Key.appearance)
            appearance.apply()
        }
    }

    init() {
        clipboardRetention =
            ClipboardRetention(rawValue: defaults.integer(forKey: Key.clipboardRetention))
            ?? .threeMonths
        clipboardDisabledApps =
            defaults.stringArray(forKey: Key.clipboardDisabledApps)
            ?? ["com.apple.keychainaccess", "com.apple.Passwords"]
        openOnCursorScreen =
            defaults.object(forKey: Key.openOnCursorScreen) == nil
            || defaults.bool(forKey: Key.openOnCursorScreen)
        launchAtLogin = LaunchAtLogin.isEnabled
        switchToEnglishInputOnOpen = defaults.bool(forKey: Key.switchToEnglishInputOnOpen)
        language =
            defaults.string(forKey: Key.language).flatMap(AppLanguage.init(rawValue:)) ?? .system
        appearance =
            defaults.string(forKey: Key.appearance).flatMap(AppAppearance.init(rawValue:))
            ?? .system
    }
}
