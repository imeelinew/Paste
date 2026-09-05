import AppKit
import LinkPresentation
import SwiftUI

struct RootPaletteView: View {
    let visualStyle: PaletteVisualStyle

    var body: some View {
        switch visualStyle {
        case .daycast:
            DaycastPaletteView()
        case .past:
            PastPaletteView()
        }
    }
}

private struct DaycastPaletteView: View {
    @EnvironmentObject private var vm: PaletteViewModel
    @ObservedObject private var settings = AppCore.shared.settings

    @State private var scroll = ScrollIntent(kind: .top)

    private var isQueryEmpty: Bool {
        vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showActions: Bool {
        if case .actions = vm.overlay { return true }
        return false
    }

    private var showAppMenu: Bool { vm.overlay == .appMenu }
    private var showTypeFilter: Bool { vm.overlay == .typeFilter }
    private var showRename: Bool { vm.renamingID != nil }

    @MainActor
    private var menuItems: [PopoverMenuItem] {
        vm.menuActions.map {
            PopoverMenuItem(action: $0, target: vm.pasteTarget, kindFilter: vm.kindFilter)
        }
    }

    var body: some View {
        let clips = vm.results
        let selected = vm.selectedItem

        return Group {
            if clips.isEmpty {
                EmptyResults(
                    text: isQueryEmpty && vm.kindFilter == .all
                        ? "Clipboard history is empty" : "No matching entries",
                    systemImage: "magnifyingglass"
                )
            } else {
                HStack(spacing: 0) {
                    ClipboardList(
                        results: clips,
                        selectedID: vm.selectedID,
                        query: vm.query,
                        scroll: scroll,
                        hoverEnabled: !vm.menuOpen && !showRename,
                        onSelect: { vm.select($0.id) },
                        onActions: { item in vm.openActions(for: item.id) },
                        renamingID: vm.renamingID,
                        renameDraft: vm.renameDraft,
                        onCommitRename: { vm.commitOpenRename($0) }
                    )
                    .frame(width: Theme.Size.clipboardListWidth)
                    Rectangle()
                        .fill(Theme.Colors.separator)
                        .frame(width: 1)
                    ClipboardPreview(item: selected, query: vm.query)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar(showActionGroup: selected != nil)
                .allowsHitTesting(!showRename)
        }
        .overlay {
            if vm.menuOpen {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { vm.closeMenu() }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if showAppMenu {
                PopoverMenu(
                    items: menuItems,
                    selection: $vm.menuSelection,
                    onActivate: activateMenuItem
                )
                .padding(Self.menuInset)
                .transition(Self.menuTransition(.bottomLeading))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showActions {
                PopoverMenu(
                    items: menuItems,
                    selection: $vm.menuSelection,
                    onActivate: activateMenuItem
                )
                .padding(Self.menuInset)
                .transition(Self.menuTransition(.bottomTrailing))
            }
        }
        .overlay(alignment: .topTrailing) {
            if showTypeFilter {
                PopoverMenu(
                    items: menuItems,
                    selection: $vm.menuSelection,
                    onActivate: activateMenuItem
                )
                .padding(.top, Theme.Size.headerPadding + Theme.Size.headerHeight)
                .padding(.trailing, Theme.Spacing.md * 2)
                .transition(Self.menuTransition(.topTrailing))
            }
        }
        .animation(Self.menuAnimation, value: vm.overlay)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .onAppear {
            if vm.selectedGroupID != nil { vm.selectGroup(nil) }
        }
        .onChange(of: vm.resetToken) {
            scroll = ScrollIntent(kind: .top)
        }
        .onChange(of: vm.followToken) {
            scroll = ScrollIntent(kind: .follow)
        }
        .environment(\.locale, settings.language.locale)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            PaletteSearchField(text: $vm.query, enabled: !showRename, fontSize: 20)
                .frame(maxWidth: .infinity)
            typeFilterControl
                .allowsHitTesting(!showRename)
        }
        .padding(.horizontal, Theme.Spacing.md * 2)
        .frame(height: Theme.Size.headerHeight)
        .padding(.top, Theme.Size.headerPadding)
        .frame(maxWidth: .infinity)
    }

    private var typeFilterControl: some View {
        BarButton(pressed: showTypeFilter, action: { vm.toggleTypeFilter() }) {
            HStack(spacing: Theme.Spacing.sm) {
                LucideIconShape(name: vm.kindFilter.icon)
                    .stroke(
                        style: StrokeStyle(
                            lineWidth: LucideIcon.strokeWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(width: LucideIcon.size, height: LucideIcon.size)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(vm.kindFilter.title)
                    .font(Theme.Typography.bar)
                    .foregroundStyle(.primary)
                LucideIconShape(name: .chevronDown)
                    .stroke(
                        style: StrokeStyle(
                            lineWidth: LucideIcon.strokeWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(width: 12, height: 12)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.xs)
        .frosted(in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(vm.kindFilter.title)
    }

    private func bottomBar(showActionGroup: Bool) -> some View {
        HStack(spacing: 0) {
            MenuCircleButton(pressed: showAppMenu) { vm.toggleAppMenu() }
            Spacer()
            if showActionGroup { actionGroup }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Size.bottomBarHeight)
        .frame(maxWidth: .infinity)
    }

    @MainActor
    private var actionGroup: some View {
        HStack(spacing: 2) {
            BarButton(action: { vm.handle(.activate) }) {
                HStack(spacing: Theme.Spacing.sm) {
                    if let path = vm.pasteTarget?.iconPath {
                        MenuFileIcon(path: path)
                    }
                    Text(vm.pasteTarget?.pasteTitle ?? LocalizedStringKey("Paste"))
                        .font(Theme.Typography.bar)
                        .foregroundStyle(.primary)
                    KeyCapChip(text: "↵", style: .outline)
                }
            }
            BarButton(pressed: showActions, action: { vm.handle(.toggleActions) }) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Actions")
                        .font(Theme.Typography.bar)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    if let shortcut = PaletteShortcut.actions.displayString {
                        HStack(spacing: Theme.Spacing.xxs) {
                            ForEach(Array(shortcut.enumerated()), id: \.offset) { _, glyph in
                                KeyCapChip(text: String(glyph), style: .outline)
                            }
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.xs)
        .frosted(in: Capsule())
    }

    private func activateMenuItem(_ index: Int) {
        vm.activateMenuItem(at: index)
    }

    private static let menuInset: CGFloat = 8
    private static let menuAnimation: Animation = .easeOut(duration: 0.14)

    private static func menuTransition(_ anchor: UnitPoint) -> AnyTransition {
        .opacity.combined(with: .scale(scale: 0.96, anchor: anchor))
    }
}

private struct PastPaletteView: View {
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var vm: PaletteViewModel
    @EnvironmentObject private var store: ClipboardStore
    @ObservedObject private var settings = AppCore.shared.settings

    @State private var groupDialog: GroupDialog?
    @State private var groupDraft = ""
    @State private var groupColor: ClipboardGroupColor = .blue
    @State private var searchExpanded = false

    private var showActions: Bool {
        if case .actions = vm.overlay { return true }
        return false
    }

    @MainActor
    private var actionMenuItems: [PopoverMenuItem] {
        vm.menuActions.map {
            PopoverMenuItem(action: $0, target: vm.pasteTarget, kindFilter: vm.kindFilter)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            shelf
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .overlay {
            if vm.menuOpen {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { vm.closeMenu() }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showActions {
                PopoverMenu(
                    items: actionMenuItems,
                    selection: $vm.menuSelection,
                    onActivate: vm.activateMenuItem
                )
                .padding(Theme.Spacing.xl)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
            }
        }
        .animation(.easeOut(duration: 0.14), value: vm.overlay)
        .overlay(alignment: .top) {
            if groupDialog != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { groupDialog = nil }
                groupEditor
                    .padding(.top, 52)
            }
        }
        .environment(\.locale, settings.language.locale)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .frame(width: 30)
                .accessibilityLabel("Clipboard")
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                searchControl
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ClipboardGroupButton(
                            title: String(localized: "Clipboard", locale: settings.language.locale),
                            color: .secondary,
                            selected: vm.selectedGroupID == nil,
                            systemImage: "clock.arrow.circlepath"
                        ) { vm.selectGroup(nil) }
                        ForEach(store.groups) { group in
                            ClipboardGroupButton(
                                title: group.name, color: group.color.swiftUIColor,
                                selected: vm.selectedGroupID == group.id
                            ) { vm.selectGroup(group.id) }
                            .contextMenu {
                                Button("Rename") { presentRename(group) }
                                ShareLink(item: shareText(for: group)) { Text("Share Pinboard") }
                                Button("Delete Pinboard…") { groupDialog = .delete(group) }
                                Divider()
                                ControlGroup {
                                    ForEach(ClipboardGroupColor.allCases) { color in
                                        Button { store.setColor(color, for: group) } label: {
                                            Image(systemName: color == group.color ? "circle.inset.filled" : "circle.fill")
                                                .foregroundStyle(color.swiftUIColor)
                                                .accessibilityLabel(color.title)
                                        }
                                    }
                                }
                                .controlGroupStyle(.palette)
                            }
                            .dropDestination(for: String.self) { values, _ in
                                guard let value = values.first, let itemID = UUID(uuidString: value)
                                else { return false }
                                store.setItem(itemID, in: group.id, member: true)
                                return true
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .fixedSize(horizontal: false, vertical: true)
                Button(action: presentCreateGroup) {
                    Image(systemName: "plus")
                        .font(.system(size: 19, weight: .regular))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Pinboard")
            }
            .frame(maxWidth: 900)
            Spacer(minLength: 0)
            PasteApplicationMenu()
        }
        .padding(.horizontal, 20)
        .frame(height: Theme.Size.shelfHeaderHeight)
    }

    private var searchControl: some View {
        HStack(spacing: 8) {
            Button {
                searchExpanded.toggle()
                vm.onSearchFocusRequested?()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .frame(width: 28, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")
            PaletteSearchField(text: $vm.query, enabled: vm.renamingID == nil && groupDialog == nil)
                .frame(width: searchExpanded || !vm.query.isEmpty ? 180 : 1, height: 30)
                .opacity(searchExpanded || !vm.query.isEmpty ? 1 : 0)
        }
    }

    private var groupEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(dialogTitle).font(.headline)
            if case .delete(let group) = groupDialog {
                Text("Delete “\(group.name)” and keep its clipboard items?")
                HStack {
                    Spacer()
                    Button("Cancel") { groupDialog = nil }
                    Button("Delete", role: .destructive) { delete(group) }
                }
            } else {
                PinboardNameField(text: $groupDraft, onSave: saveGroupDialog,
                                  onCancel: { groupDialog = nil })
                    .frame(height: 28)
                    .padding(.horizontal, 8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                HStack(spacing: 10) {
                    ForEach(ClipboardGroupColor.allCases) { color in
                        Button { groupColor = color } label: {
                            Circle().fill(color.swiftUIColor)
                                .frame(width: 20, height: 20)
                                .padding(3)
                                .overlay {
                                    Circle().strokeBorder(
                                        groupColor == color ? Color.primary.opacity(0.3) : .clear,
                                        lineWidth: 2)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(color.title)
                    }
                }
                HStack {
                    Spacer()
                    Button("Cancel") { groupDialog = nil }
                    Button("Save") { saveGroupDialog() }
                        .buttonStyle(.borderedProminent)
                        .disabled(groupDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(18)
        .frame(width: 310)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.4), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
    }

    @ViewBuilder
    private var shelf: some View {
        if vm.results.isEmpty {
            EmptyResults(
                text: vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && vm.selectedGroupID == nil
                    ? "Clipboard history is empty" : "No matching entries")
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .center, spacing: Theme.Size.cardSpacing) {
                        ForEach(Array(vm.results.enumerated()), id: \.element.id) { index, item in
                            ClipboardShelfCard(
                                item: item,
                                selected: vm.selectedID == item.id,
                                selectedGroupID: vm.selectedGroupID,
                                ordinal: index + 1,
                                onSelect: { vm.select(item.id) },
                                onCommitRename: vm.commitOpenRename
                            )
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, Theme.Size.shelfInset)
                    .padding(.vertical, Theme.Spacing.md)
                }
                .scrollIndicators(.hidden)
                .frame(height: Theme.Size.cardHeight + 16)
                .onChange(of: vm.followToken) {
                    guard let selectedID = vm.selectedID else { return }
                    proxy.scrollTo(selectedID)
                }
                .onChange(of: vm.resetToken) {
                    guard let first = vm.results.first else { return }
                    proxy.scrollTo(first.id, anchor: .leading)
                }
            }
        }
    }

    private var dialogTitle: LocalizedStringKey {
        switch groupDialog {
        case .create: "New Pinboard"
        case .rename: "Rename Pinboard"
        case .delete: "Delete Pinboard?"
        case nil: "Pinboard"
        }
    }

    private func presentCreateGroup() {
        groupDraft = ""
        groupColor = .blue
        groupDialog = .create
    }

    private func presentRename(_ group: ClipboardGroup) {
        groupDraft = group.name
        groupColor = group.color
        groupDialog = .rename(group)
    }

    private func saveGroupDialog() {
        guard !groupDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        switch groupDialog {
        case .create:
            if let group = store.createGroup(named: groupDraft, color: groupColor) {
                vm.selectGroup(group.id)
            }
        case .rename(let group):
            store.renameGroup(group, to: groupDraft)
            store.setColor(groupColor, for: group)
        case .delete, nil:
            break
        }
        groupDialog = nil
    }

    private func delete(_ group: ClipboardGroup) {
        if vm.selectedGroupID == group.id { vm.selectGroup(nil) }
        store.deleteGroup(group)
        groupDialog = nil
    }

    private func shareText(for group: ClipboardGroup) -> String {
        let ids = store.itemIDs(in: group.id)
        let values = store.displayItems.filter { ids.contains($0.id) }.map { item in
            item.text ?? String(localized: "Image", locale: settings.language.locale)
        }
        return ([group.name] + values).joined(separator: "\n\n")
    }
}

private enum GroupDialog: Identifiable {
    case create
    case rename(ClipboardGroup)
    case delete(ClipboardGroup)

    var id: String {
        switch self {
        case .create: "create"
        case .rename(let group): "rename-\(group.id)"
        case .delete(let group): "delete-\(group.id)"
        }
    }
}

private struct ClipboardGroupButton: View {
    let title: String
    let color: Color
    let selected: Bool
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .medium))
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 9, height: 9)
                }
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(height: 34)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(selected ? Color.primary.opacity(0.08) : .clear, in: Capsule())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct PasteApplicationMenu: View {
    @EnvironmentObject private var core: AppCore

    var body: some View {
        Menu {
            Button("About Paste") { core.showAbout() }
            Divider()
            Button("New Text Item") { core.createTextItem() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Settings…") { core.showSettings() }
                .keyboardShortcut(",", modifiers: .command)
            Divider()
            if core.isClipboardPaused {
                Button("Resume Paste") { core.resumeClipboard() }
            } else {
                Menu("Pause Paste") {
                    Button("For 15 Minutes") {
                        core.pauseClipboard(until: Date().addingTimeInterval(15 * 60))
                    }
                    Button("For 1 Hour") {
                        core.pauseClipboard(until: Date().addingTimeInterval(60 * 60))
                    }
                    Button("Until Tomorrow") {
                        let calendar = Calendar.current
                        let tomorrow = calendar.date(
                            byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
                        core.pauseClipboard(until: tomorrow)
                    }
                    Button("Indefinitely") { core.pauseClipboard(until: nil) }
                }
            }
            Divider()
            Button("Quit Paste") { core.requestQuit() }
                .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Paste Menu")
    }
}

private struct ClipboardShelfCard: View {
    let item: ClipboardItem
    let selected: Bool
    let selectedGroupID: ClipboardGroup.ID?
    let ordinal: Int
    let onSelect: () -> Void
    let onCommitRename: (String) -> Void

    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var vm: PaletteViewModel
    @ObservedObject private var settings = AppCore.shared.settings
    @State private var source: ShelfSource?
    @State private var characterCount = 0
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

    private var isRenaming: Bool { vm.renamingID == item.id }

    var body: some View {
        Button(action: onSelect) {
            cardContent
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.shelfCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.shelfCard, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: selected ? 4 : 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.shelfCard, style: .continuous))
        .task(id: item.sourceBundleID) {
            source = await ShelfSourceCache.load(item.sourceBundleID)
        }
        .task(id: item.text) {
            let text = item.text
            let count = await Task.detached(priority: .utility) { text?.count ?? 0 }.value
            if !Task.isCancelled { characterCount = count }
        }
        .contextMenu { itemContextMenu }
        .draggable(item.id.uuidString) {
            Text(item.displayTitle(locale: settings.language.locale))
                .lineLimit(1)
                .padding(Theme.Spacing.md)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .onChange(of: isRenaming, initial: true) { _, renaming in
            guard renaming else { return }
            renameText = item.displayTitle(locale: settings.language.locale)
            renameFocused = true
        }
        .onChange(of: renameFocused) { wasFocused, isFocused in
            if wasFocused, !isFocused, isRenaming { onCommitRename(renameText) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.displayTitle(locale: settings.language.locale))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            cardHeader
            cardBody
            if item.kind != .link || isRenaming { cardFooter }
        }
        .frame(width: Theme.Size.cardWidth, height: Theme.Size.cardHeight)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var cardHeader: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(item.kind == .image ? "Image" : item.kind == .link ? "Link" : "Text")
                    .font(.headline.weight(.semibold))
                Text(item.createdAt, style: .relative)
                    .font(.caption)
                    .opacity(0.82)
            }
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let source {
                Image(nsImage: source.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.9), in: UnevenRoundedRectangle(topLeadingRadius: 10))
            }
        }
        .foregroundStyle(Color.white)
        .frame(height: Theme.Size.cardHeaderHeight)
        .background(accent)
    }

    @ViewBuilder
    private var cardBody: some View {
        switch item.kind {
        case .image:
            ShelfImage(url: store.imageURL(for: item))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .link:
            ShelfLinkPreview(text: item.text ?? "", customTitle: item.customTitle)
        case .text, .code:
            Text(verbatim: String((item.text ?? "").prefix(1_400)))
                .font(item.kind == .code ? .system(size: 14, design: .monospaced) : .system(size: 15))
                .foregroundStyle(Color(nsColor: .textColor))
                .lineSpacing(3)
                .lineLimit(item.kind == .link ? 6 : 9)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(Theme.Spacing.xl)
        }
    }

    private var cardFooter: some View {
        HStack(spacing: 6) {
            if isRenaming {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.callout.weight(.semibold))
                    .focused($renameFocused)
                    .onSubmit { onCommitRename(renameText) }
            } else {
                Spacer(minLength: 0)
                if item.kind != .image {
                    if let title = item.customTitle {
                        Text(verbatim: title).lineLimit(1)
                    } else {
                        Text("\(characterCount) Characters")
                    }
                }
                Spacer(minLength: 0)
                Label("\(ordinal)", systemImage: "text.alignleft")
                    .font(.system(size: 11))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(0.07), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: Theme.Size.cardFooterHeight)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var itemContextMenu: some View {
        Button("Paste") { perform(.activate) }
        Button("Copy to Clipboard") { perform(.copy) }
        Button("Rename") { perform(.rename) }
        Button(item.isPinned ? "Unpin Entry" : "Pin Entry") { perform(.togglePin) }
        if item.kind == .image {
            Button("Show in Finder") { perform(.revealInFinder) }
        }
        if !store.groups.isEmpty {
            Divider()
            Menu("Pinboards") {
                ForEach(store.groups) { group in
                    Button {
                        store.toggleItem(item.id, in: group.id)
                    } label: {
                        Label(
                            group.name,
                            systemImage: store.contains(item.id, in: group.id)
                                ? "checkmark.circle.fill" : "circle"
                        )
                    }
                }
            }
        }
        Divider()
        Button("Delete Entry", role: .destructive) { performDelete() }
    }

    private var accent: Color {
        source.map { Color(nsColor: $0.color) } ?? Color.gray
    }

    private func perform(_ command: PaletteCommand) {
        vm.select(item.id)
        _ = vm.handle(command)
    }

    private func performDelete() {
        vm.select(item.id)
        vm.openActions(for: item.id)
        if let index = vm.menuActions.firstIndex(where: {
            if case .delete = $0 { return true }
            return false
        }) {
            vm.activateMenuItem(at: index)
        }
    }
}

private struct PinboardNameField: NSViewRepresentable {
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PinboardTextField {
        let field = PinboardTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.placeholderString = String(localized: "Name")
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: PinboardTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    static func dismantleNSView(_ field: PinboardTextField, coordinator: Coordinator) {
        field.palette?.auxiliaryInputActive = false
        field.palette?.requestSearchFocus()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PinboardNameField
        init(_ parent: PinboardNameField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSave()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

private final class PinboardTextField: NSTextField {
    weak var palette: PalettePanel?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let panel = window as? PalettePanel else { return }
        palette = panel
        panel.auxiliaryInputActive = true
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, self.window === panel else { return }
            panel.makeFirstResponder(self)
            self.selectText(nil)
        }
    }
}

private struct ShelfSource: @unchecked Sendable {
    let icon: NSImage
    let color: NSColor
}

private actor ShelfSourceCache {
    private static let shared = ShelfSourceCache()
    private var pending: [String: Task<ShelfSource?, Never>] = [:]

    static func load(_ bundleID: String?) async -> ShelfSource? {
        guard let bundleID else { return nil }
        return await shared.source(bundleID)
    }

    private func source(_ bundleID: String) async -> ShelfSource? {
        if let task = pending[bundleID] { return await task.value }
        let task = Task.detached(priority: .utility) { () -> ShelfSource? in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            else { return nil }
            let icon = IconCache.icon(forFile: url.path)
            var color = NSColor(calibratedWhite: 0.55, alpha: 1)
            if let bitmap = icon.representations.first as? NSBitmapImageRep {
                var red = 0.0, green = 0.0, blue = 0.0, weight = 0.0
                for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
                    for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                        guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                              pixel.alphaComponent > 0.5 else { continue }
                        let saturation = pixel.saturationComponent
                        let w = 0.1 + saturation * saturation
                        red += pixel.redComponent * w
                        green += pixel.greenComponent * w
                        blue += pixel.blueComponent * w
                        weight += w
                    }
                }
                if weight > 0 {
                    color = NSColor(calibratedRed: red / weight, green: green / weight,
                                    blue: blue / weight, alpha: 1)
                }
            }
            if bundleID.lowercased().contains("openai") {
                color = NSColor(calibratedRed: 0.025, green: 0.055, blue: 0.20, alpha: 1)
            }
            return ShelfSource(icon: icon, color: color)
        }
        pending[bundleID] = task
        return await task.value
    }
}

private struct ShelfLinkPreview: View {
    let text: String
    let customTitle: String?
    @State private var preview: ShelfLinkData?

    private var url: URL? { URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let image = preview?.image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .padding(16)
                } else {
                    Image(systemName: "link")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.primary.opacity(0.025))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: customTitle ?? preview?.title ?? url?.host ?? text)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(verbatim: url?.host ?? text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 48)
        }
        .task(id: url) {
            guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
            // Avoid starting page requests for cards swept past during a fast scroll.
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            preview = await ShelfLinkCache.load(url)
        }
    }
}

private final class ShelfLinkData: @unchecked Sendable {
    let title: String?
    let image: NSImage?
    init(title: String?, image: NSImage?) { self.title = title; self.image = image }
}

private struct ShelfMetadataResult: @unchecked Sendable {
    let metadata: LPLinkMetadata?
}

@MainActor
private final class ShelfMetadataRequest {
    private let provider = LPMetadataProvider()

    func fetch(_ url: URL) async -> ShelfMetadataResult {
        provider.timeout = 6
        return await withCheckedContinuation { continuation in
            provider.startFetchingMetadata(for: url) { metadata, _ in
                continuation.resume(returning: ShelfMetadataResult(metadata: metadata))
            }
        }
    }

    func cancel() { provider.cancel() }
}

@MainActor
private enum ShelfLinkCache {
    private static let cache: NSCache<NSURL, ShelfLinkData> = {
        let cache = NSCache<NSURL, ShelfLinkData>()
        cache.countLimit = 100
        return cache
    }()

    static func load(_ url: URL) async -> ShelfLinkData? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let request = ShelfMetadataRequest()
        let result = await withTaskCancellationHandler {
            await request.fetch(url)
        } onCancel: {
            Task { @MainActor in request.cancel() }
        }
        guard !Task.isCancelled, let metadata = result.metadata else { return nil }
        let title = metadata.title
        var data = ShelfLinkData(title: title, image: nil)
        if let images = metadata.imageProvider {
            data = await withCheckedContinuation { continuation in
                _ = images.loadObject(ofClass: NSImage.self) { object, _ in
                    continuation.resume(returning: ShelfLinkData(title: title, image: object as? NSImage))
                }
            }
        }
        guard !Task.isCancelled else { return nil }
        cache.setObject(data, forKey: url as NSURL)
        return data
    }
}

private struct ShelfImage: View {
    let url: URL?
    @State private var image: NSImage?
    @State private var dimensions: CGSize?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 36))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)
            }
        }
        .background {
            Canvas { context, size in
                let tile: CGFloat = 8
                for row in 0..<Int(ceil(size.height / tile)) {
                    for column in 0..<Int(ceil(size.width / tile)) where (row + column).isMultiple(of: 2) {
                        context.fill(Path(CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile,
                                                 width: tile, height: tile)),
                                     with: .color(.gray.opacity(0.12)))
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let dimensions {
                Text(verbatim: "\(Int(dimensions.width)) × \(Int(dimensions.height))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 3)
            }
        }
        .task(id: url) {
            dimensions = nil
            guard let url else { return }
            image = ImageThumbnail.cached(url, maxPixel: 520)
            image = await ImageThumbnail.loadAsync(url, maxPixel: 520)
            let size = await Task.detached(priority: .utility) { ImageThumbnail.pixelSize(of: url) }.value
            if !Task.isCancelled { dimensions = size }
        }
    }
}

private struct PaletteSearchField: NSViewRepresentable {
    @Binding var text: String
    let enabled: Bool
    var fontSize: CGFloat = 17

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSTextField {
        let field = PaletteSearchTextField(frame: .zero)
        field.delegate = context.coordinator
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize, weight: .regular)
        field.textColor = .labelColor
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.setAccessibilityLabel(String(localized: "Search"))
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        field.isEnabled = enabled
        field.font = .systemFont(ofSize: fontSize, weight: .regular)
        field.placeholderAttributedString = NSAttributedString(
            string: String(localized: "Search", locale: context.environment.locale),
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        )
        if !enabled, field.currentEditor() != nil { field.window?.makeFirstResponder(nil) }
        (field.window as? PalettePanel)?.registerSearchField(field)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField,
                text.wrappedValue != field.stringValue
            else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

private final class PaletteSearchTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        (window as? PalettePanel)?.registerSearchField(self)
    }
}

private struct MenuCircleButton: View {
    var pressed: Bool = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Capsule().frame(width: 14, height: 1.5)
                Capsule().frame(width: 8, height: 1.5)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(width: Theme.Size.menuButton, height: Theme.Size.menuButton)
            .background(
                Circle().fill(pressed || hovered ? Theme.Colors.selection : Color.clear)
            )
            .contentShape(.circle)
            .scaleEffect(pressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.08), value: pressed)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .frosted(in: Circle())
    }
}

private struct BarButton<Label: View>: View {
    var pressed: Bool = false
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: 28)
                .contentShape(Capsule())
                .background(
                    Capsule().fill(
                        pressed || hovered ? Theme.Colors.rowHover : Color.clear
                    )
                )
                .scaleEffect(pressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.08), value: pressed)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

struct EmptyResults: View {
    let text: LocalizedStringKey
    var systemImage = "rectangle.stack"

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension ClipboardGroupColor {
    var swiftUIColor: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .gray: "Gray"
        }
    }
}
