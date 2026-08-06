import SwiftUI

extension Notification.Name {
    static let pasteSelectSettingsTab = Notification.Name("PasteSelectSettingsTab")
}

enum SettingsTab: Int, CaseIterable, Hashable, Identifiable {
    case general, appearance, history

    var id: Int { rawValue }

    var localizationKey: String.LocalizationValue {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .history: return "History"
        }
    }

    /// Stable identifier for `MacAppSettingsUI` tab items.
    var tabIdentifier: String {
        switch self {
        case .general: return "general"
        case .appearance: return "appearance"
        case .history: return "history"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "eyeglasses"
        case .history: return "clock"
        }
    }

    var preferredPaneHeight: CGFloat {
        switch self {
        case .general: return 300
        case .appearance: return 180
        case .history: return 360
        }
    }
}
