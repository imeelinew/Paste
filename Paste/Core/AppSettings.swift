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

enum PinnedImageSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var longestEdge: CGFloat {
        switch self {
        case .small: return 360
        case .medium: return 480
        case .large: return 640
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard
    private var reconcilingLaunchAtLogin = false

    private enum Key {
        static let clipboardRetention = "clipboardRetentionDays"
        static let clipboardDisabledApps = "clipboardDisabledApps"
        static let launchAtLogin = "launchAtLogin"
        static let switchToEnglishInputOnOpen = "switchToEnglishInputOnOpen"
        static let renderMarkdown = "renderMarkdown"
        static let language = "appLanguage"
        static let appearance = "appAppearance"
        static let pinnedImageSize = "pinnedImageSize"
    }

    @Published var clipboardRetention: ClipboardRetention {
        didSet { defaults.set(clipboardRetention.rawValue, forKey: Key.clipboardRetention) }
    }

    @Published var clipboardDisabledApps: [String] {
        didSet { defaults.set(clipboardDisabledApps, forKey: Key.clipboardDisabledApps) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !reconcilingLaunchAtLogin else { return }
            let actual = LaunchAtLogin.set(launchAtLogin)
            defaults.set(actual, forKey: Key.launchAtLogin)
            guard actual != launchAtLogin else { return }
            reconcilingLaunchAtLogin = true
            launchAtLogin = actual
            reconcilingLaunchAtLogin = false
        }
    }

    /// When enabled, opening the palette selects the English keyboard so pinyin search can be typed directly.
    @Published var switchToEnglishInputOnOpen: Bool {
        didSet { defaults.set(switchToEnglishInputOnOpen, forKey: Key.switchToEnglishInputOnOpen) }
    }

    @Published var renderMarkdown: Bool {
        didSet { defaults.set(renderMarkdown, forKey: Key.renderMarkdown) }
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

    @Published var pinnedImageSize: PinnedImageSize {
        didSet { defaults.set(pinnedImageSize.rawValue, forKey: Key.pinnedImageSize) }
    }

    init() {
        clipboardRetention =
            ClipboardRetention(rawValue: defaults.integer(forKey: Key.clipboardRetention))
            ?? .threeMonths
        clipboardDisabledApps =
            defaults.stringArray(forKey: Key.clipboardDisabledApps)
            ?? ["com.apple.keychainaccess", "com.apple.Passwords"]
        launchAtLogin = LaunchAtLogin.isEnabled
        switchToEnglishInputOnOpen = defaults.bool(forKey: Key.switchToEnglishInputOnOpen)
        renderMarkdown = defaults.object(forKey: Key.renderMarkdown) as? Bool ?? true
        language =
            defaults.string(forKey: Key.language).flatMap(AppLanguage.init(rawValue:)) ?? .system
        appearance =
            defaults.string(forKey: Key.appearance).flatMap(AppAppearance.init(rawValue:))
            ?? .system
        pinnedImageSize =
            defaults.string(forKey: Key.pinnedImageSize).flatMap(PinnedImageSize.init(rawValue:))
            ?? .medium
    }
}
