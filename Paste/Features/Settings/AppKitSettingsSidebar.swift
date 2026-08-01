import AppKit
import SwiftUI

/// Obelisk-style source-list sidebar. SwiftUI keeps owning the selected tab while AppKit owns
/// native row layout and the deliberately unemphasized (neutral, never accent-blue) selection.
struct AppKitSettingsSidebar: NSViewRepresentable {
    let tabs: [SettingsTab]
    @Binding var selectedTab: SettingsTab
    let locale: Locale

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.reload()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: AppKitSettingsSidebar
        private weak var tableView: NSTableView?
        private var isSyncingSelection = false

        init(parent: AppKitSettingsSidebar) {
            self.parent = parent
            super.init()
        }

        func makeScrollView() -> NSScrollView {
            let scrollView = NSScrollView()
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.horizontalScrollElasticity = .none
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

            let tableView = NSTableView()
            tableView.frame = scrollView.contentView.bounds
            tableView.autoresizingMask = [.width]
            tableView.delegate = self
            tableView.dataSource = self
            tableView.headerView = nil
            tableView.backgroundColor = .clear
            tableView.style = .sourceList
            tableView.selectionHighlightStyle = .regular
            tableView.rowSizeStyle = .custom
            tableView.intercellSpacing = NSSize(width: 0, height: 2)
            tableView.allowsMultipleSelection = false
            tableView.allowsEmptySelection = false
            tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

            let column = NSTableColumn(identifier: .pasteSettingsSidebarColumn)
            column.resizingMask = .autoresizingMask
            tableView.addTableColumn(column)

            scrollView.documentView = tableView
            self.tableView = tableView
            syncSelection(in: tableView)
            return scrollView
        }

        func reload() {
            guard let tableView else { return }
            syncTableWidth(tableView)
            reloadVisibleRows(in: tableView)
            syncSelection(in: tableView)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.tabs.count
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            parent.tabs.indices.contains(row)
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            30
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            SettingsSidebarRowView()
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard parent.tabs.indices.contains(row) else { return nil }
            let cell = tableView.makeView(
                withIdentifier: SettingsSidebarPageCell.reuseIdentifier,
                owner: self
            ) as? SettingsSidebarPageCell ?? SettingsSidebarPageCell()
            cell.configure(
                tab: parent.tabs[row],
                locale: parent.locale,
                isSelected: tableView.selectedRow == row
            )
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection,
                let tableView = notification.object as? NSTableView,
                parent.tabs.indices.contains(tableView.selectedRow)
            else { return }

            let selectedRow = tableView.selectedRow
            let selectedTab = parent.tabs[selectedRow]
            applySelectionStyleToVisibleRows(in: tableView)

            // AppKit can notify while SwiftUI is updating the representable (for example when
            // accessibility changes selection). Defer the binding write to the next run loop so
            // the sidebar remains a well-behaved SwiftUI bridge in every input path.
            DispatchQueue.main.async { [weak self, weak tableView] in
                guard let self,
                    let tableView,
                    tableView.selectedRow == selectedRow,
                    self.parent.selectedTab != selectedTab
                else { return }
                self.parent.selectedTab = selectedTab
            }
        }

        private func syncSelection(in tableView: NSTableView) {
            guard let row = parent.tabs.firstIndex(of: parent.selectedTab) else { return }
            if tableView.selectedRow != row {
                isSyncingSelection = true
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                isSyncingSelection = false
            }
            applySelectionStyleToVisibleRows(in: tableView)
        }

        private func applySelectionStyleToVisibleRows(in tableView: NSTableView) {
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            guard visibleRows.location != NSNotFound else { return }
            for row in visibleRows.location ..< NSMaxRange(visibleRows) {
                guard let cell = tableView.view(
                    atColumn: 0,
                    row: row,
                    makeIfNecessary: false
                ) as? SettingsSidebarPageCell else { continue }
                cell.applySelectionStyle(isSelected: tableView.selectedRow == row)
            }
        }

        private func reloadVisibleRows(in tableView: NSTableView) {
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            guard visibleRows.location != NSNotFound else { return }
            for row in visibleRows.location ..< NSMaxRange(visibleRows) {
                guard parent.tabs.indices.contains(row),
                    let cell = tableView.view(
                        atColumn: 0,
                        row: row,
                        makeIfNecessary: false
                    ) as? SettingsSidebarPageCell
                else { continue }
                cell.configure(
                    tab: parent.tabs[row],
                    locale: parent.locale,
                    isSelected: tableView.selectedRow == row
                )
            }
        }

        private func syncTableWidth(_ tableView: NSTableView) {
            guard let scrollView = tableView.enclosingScrollView else { return }
            let width = max(scrollView.contentView.bounds.width, 100)
            tableView.frame.size.width = width
            tableView.tableColumns.first?.width = width
        }
    }
}

/// This is the essential Obelisk behavior: selected source-list rows are always rendered as
/// unemphasized, so macOS uses its neutral graphite selection instead of the user's accent color.
private final class SettingsSidebarRowView: NSTableRowView {
    override var isSelected: Bool {
        didSet { applySelectionStyleToCell() }
    }

    override var isEmphasized: Bool {
        get { false }
        set { super.isEmphasized = false }
    }

    private func applySelectionStyleToCell() {
        for subview in subviews {
            (subview as? SettingsSidebarPageCell)?.applySelectionStyle(isSelected: isSelected)
        }
    }
}

private final class SettingsSidebarPageCell: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("SettingsSidebarPageCell")
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseIdentifier

        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleField.lineBreakMode = .byTruncatingTail
        titleField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titleField)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(tab: SettingsTab, locale: Locale, isSelected: Bool) {
        titleField.stringValue = tab.localizedTitle(locale: locale)
        iconView.image = tab.professionalGradientIcon
        iconView.contentTintColor = nil
        applySelectionStyle(isSelected: isSelected)
    }

    func applySelectionStyle(isSelected: Bool) {
        titleField.font = .systemFont(
            ofSize: NSFont.systemFontSize,
            weight: isSelected ? .semibold : .regular
        )
    }
}

private extension SettingsTab {
    var resourceName: String {
        switch self {
        case .general: return "settings"
        case .clipboard: return "clipboard-text"
        case .permissions: return "lock"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .general: return String(localized: "General", locale: locale)
        case .clipboard: return String(localized: "Clipboard", locale: locale)
        case .permissions: return String(localized: "Permissions", locale: locale)
        }
    }

    var brightGradientColors: [NSColor] {
        switch self {
        case .general:
            return [Self.rgb(0.38, 0.78, 1.0), Self.rgb(0.18, 0.46, 0.98)]
        case .clipboard:
            return [Self.rgb(1.0, 0.48, 0.30), Self.rgb(1.0, 0.16, 0.32)]
        case .permissions:
            return [Self.rgb(0.82, 0.42, 1.0), Self.rgb(0.46, 0.20, 1.0)]
        }
    }

    var professionalGradientIcon: NSImage? {
        guard let maskImage = resourceImage,
            let gradient = NSGradient(colors: brightGradientColors)
        else { return resourceImage }

        let canvasSize = NSSize(width: 64, height: 64)
        let bounds = NSRect(origin: .zero, size: canvasSize)
        let image = NSImage(size: canvasSize)
        let iconMask = maskImage.copy() as? NSImage ?? maskImage
        iconMask.isTemplate = false

        image.lockFocus()
        NSColor.clear.setFill()
        bounds.fill()
        iconMask.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        let context = NSGraphicsContext.current
        let previousOperation = context?.compositingOperation
        context?.compositingOperation = .sourceIn
        gradient.draw(in: bounds, angle: 315)
        if let previousOperation { context?.compositingOperation = previousOperation }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    var resourceImage: NSImage? {
        let candidates = [
            Bundle.main.url(forResource: resourceName, withExtension: "svg"),
            Bundle.main.url(
                forResource: resourceName,
                withExtension: "svg",
                subdirectory: "SidebarIcons"
            ),
            Bundle.main.url(
                forResource: resourceName,
                withExtension: "svg",
                subdirectory: "Resources/SidebarIcons"
            ),
        ]
        for url in candidates.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: url) {
                let copy = image.copy() as? NSImage ?? image
                copy.isTemplate = true
                return copy
            }
        }
        let fallback = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        fallback?.isTemplate = true
        return fallback
    }

    static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let pasteSettingsSidebarColumn = NSUserInterfaceItemIdentifier(
        "PasteSettingsSidebarColumn"
    )
}
