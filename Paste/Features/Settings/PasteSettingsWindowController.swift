import AppKit
import Carbon.HIToolbox
import MacAppSettingsUI
import SwiftUI

/// Owns the MacAppSettingsUI preferences window and bridges Paste's SwiftUI panes into it.
@MainActor
final class PasteSettingsWindowController {
    private let activationPolicy: ActivationPolicyCoordinator
    private var controller: SettingsWindowController?
    private var closeObserver: NSObjectProtocol?
    private var commandWMonitor: Any?

    init(activationPolicy: ActivationPolicyCoordinator) {
        self.activationPolicy = activationPolicy
    }

    var isVisible: Bool {
        controller?.window?.isVisible == true
    }

    func show(tab: SettingsTab = .general) {
        let needsRebuild =
            controller == nil
            || controller?.tabViewController.panes.count != SettingsTab.allCases.count
        if needsRebuild {
            closeObserver = nil
            removeCommandWMonitor()
            controller = makeController()
        }
        guard let controller else { return }

        select(tab, in: controller)
        attachCloseObserverIfNeeded(to: controller.window)
        installCommandWMonitorIfNeeded()

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
                case .about:
                    AboutSettingsView()
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
                self?.removeCommandWMonitor()
                self?.activationPolicy.release("settings")
            }
        }
    }

    /// Agent apps lack File → Close, so mirror `AuxiliaryWindow` and handle ⌘W locally.
    private func installCommandWMonitorIfNeeded() {
        guard commandWMonitor == nil else { return }
        commandWMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard modifiers == .command, event.keyCode == UInt16(kVK_ANSI_W) else {
                return event
            }
            guard let window = self.controller?.window, window.isKeyWindow else {
                return event
            }
            window.performClose(nil)
            return nil
        }
    }

    private func removeCommandWMonitor() {
        if let commandWMonitor {
            NSEvent.removeMonitor(commandWMonitor)
            self.commandWMonitor = nil
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
