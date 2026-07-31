import SwiftUI

enum SettingsKey {
    static let showInMenuBar = "showInMenuBar"
}

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

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let clipboardRetention = "clipboardRetentionDays"
        static let clipboardDisabledApps = "clipboardDisabledApps"
        static let openOnCursorScreen = "openOnCursorScreen"
        static let launchAtLogin = "launchAtLogin"
        static let language = "appLanguage"
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

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Key.language) }
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
        language =
            defaults.string(forKey: Key.language).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }
}
