import SwiftUI

enum SettingsTab: Int, CaseIterable, Hashable, Identifiable {
    case general, shortcuts, appearance, history, about

    var id: Int { rawValue }

    var localizationKey: String.LocalizationValue {
        switch self {
        case .general: return "General"
        case .shortcuts: return "Shortcuts"
        case .appearance: return "Appearance"
        case .history: return "History"
        case .about: return "About"
        }
    }

    /// Stable identifier for `MacAppSettingsUI` tab items.
    var tabIdentifier: String {
        switch self {
        case .general: return "general"
        case .shortcuts: return "shortcuts"
        case .appearance: return "appearance"
        case .history: return "history"
        case .about: return "about"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .appearance: return "eyeglasses"
        case .history: return "clock"
        case .about: return "info.circle"
        }
    }

    var preferredPaneHeight: CGFloat {
        switch self {
        case .general: return 300
        case .shortcuts: return 620
        case .appearance: return 220
        case .history: return 360
        case .about: return 320
        }
    }
}
