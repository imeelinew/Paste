import AppKit
import MacAppSettingsUI
import SwiftUI

/// Owns the MacAppSettingsUI preferences window and bridges Paste's SwiftUI panes into it.
@MainActor
final class PasteSettingsWindowController {
    private let activationPolicy: ActivationPolicyCoordinator
    private var controller: SettingsWindowController?
    private var closeObserver: NSObjectProtocol?

    init(activationPolicy: ActivationPolicyCoordinator) {
        self.activationPolicy = activationPolicy
    }

    var isVisible: Bool {
        controller?.window?.isVisible == true
    }

    func show(tab: SettingsTab = .general) {
        if controller == nil {
            controller = makeController()
        }
        guard let controller else { return }

        select(tab, in: controller)
        attachCloseObserverIfNeeded(to: controller.window)

        activationPolicy.acquire("settings")
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        DispatchQueue.main.async {
            controller.window?.makeKeyAndOrderFront(nil)
        }
    }

    func focus() {
        guard let window = controller?.window else { return }
        activationPolicy.acquire("settings")
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Private

    private func makeController() -> SettingsWindowController {
        let locale = AppCore.shared.settings.language.locale
        let panes: [SettingsPaneViewController] = SettingsTab.allCases.map { tab in
            SwiftUISettingsPaneController(tab: tab, locale: locale) {
                switch tab {
                case .general:
                    GeneralSettingsView()
                case .appearance:
                    AppearanceSettingsView()
                case .history:
                    HistorySettingsView()
                }
            }
        }

        let controller = SettingsWindowController(
            with: panes,
            centersWindowPositionAlways: false,
            closesWindowWithEscapeKey: true
        )
        controller.settingsWindow.defaultWindowTitle = String(
            localized: "Paste Settings",
            locale: locale
        )
        return controller
    }

    private func select(_ tab: SettingsTab, in controller: SettingsWindowController) {
        let panes = controller.tabViewController.panes
        guard let index = panes.firstIndex(where: { $0.tabIdentifier == tab.tabIdentifier })
        else { return }
        controller.tabViewController.selectedTabIndex = index
    }

    private func attachCloseObserverIfNeeded(to window: NSWindow?) {
        guard let window, closeObserver == nil else { return }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.activationPolicy.release("settings")
            }
        }
    }
}

/// Hosts a SwiftUI settings pane inside `MacAppSettingsUI`'s `SettingsPaneViewController`.
private final class SwiftUISettingsPaneController: SettingsPaneViewController {
    private let rootView: AnyView
    private let paneHeight: CGFloat
    private static let paneWidth: CGFloat = 480

    init(
        tab: SettingsTab,
        locale: Locale,
        @ViewBuilder content: () -> some View
    ) {
        self.rootView = AnyView(
            content()
                .environment(\.locale, locale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        )
        self.paneHeight = tab.preferredPaneHeight
        super.init(nibName: nil, bundle: nil)
        tabName = String(localized: tab.localizationKey, locale: locale)
        tabImage = NSImage(systemSymbolName: tab.systemImage, accessibilityDescription: nil)
        tabIdentifier = tab.tabIdentifier
        isResizableView = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = []
        view = hosting
        preferredPaneSize = NSSize(width: Self.paneWidth, height: paneHeight)
        view.setFrameSize(preferredPaneSize ?? .zero)
    }
}
