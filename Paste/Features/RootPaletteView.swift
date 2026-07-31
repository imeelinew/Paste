import SwiftUI

struct RootPaletteView: View {
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var vm: PaletteViewModel
    @EnvironmentObject private var store: ClipboardStore

    @FocusState private var searchFocused: Bool
    @State private var showActions = false
    @State private var showAppMenu = false
    @State private var menuSelection = 0
    @State private var scroll = ScrollIntent(kind: .top)

    private var isQueryEmpty: Bool {
        vm.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var clipResults: [ClipboardItem] { store.search(vm.query) }

    private var selection: Int {
        clipResults.isEmpty ? 0 : min(max(vm.selection, 0), clipResults.count - 1)
    }

    private var selectedClipItem: ClipboardItem? {
        clipResults.indices.contains(selection) ? clipResults[selection] : nil
    }

    private var menuOpen: Bool { showActions || showAppMenu }

    private var actionsContent: PopoverMenuContent? {
        guard let item = selectedClipItem else { return nil }
        return ClipboardActionsMenu.content(
            item: item, core: core, store: store, target: vm.pasteTarget)
    }

    private var appMenuContent: PopoverMenuContent {
        PopoverMenuContent(items: [
            PopoverMenuItem(title: "About Paste", systemImage: "info.circle") {
                core.showAbout()
            },
            PopoverMenuItem(title: "Settings", systemImage: "gearshape", shortcut: "⌘,") {
                core.showSettings()
            },
        ])
    }

    private var menuContent: PopoverMenuContent? {
        if showActions { return actionsContent }
        if showAppMenu { return appMenuContent }
        return nil
    }

    var body: some View {
        let clips = clipResults
        let selectedIndex = clips.isEmpty ? 0 : min(max(vm.selection, 0), clips.count - 1)
        let selected = clips.indices.contains(selectedIndex) ? clips[selectedIndex] : nil
        let clipFollow = ClipFollowKey(id: store.items.first?.id, token: vm.followToken)

        return Group {
            if clips.isEmpty {
                EmptyResults(
                    text: isQueryEmpty ? "Clipboard history is empty" : "No matching entries")
            } else {
                HStack(spacing: 0) {
                    ClipboardList(
                        results: clips,
                        selectedID: selected?.id,
                        scroll: scroll,
                        onSelect: { item in vm.selection = clips.firstIndex(of: item) ?? 0 },
                        onActivate: activateSelection,
                        onActions: { item in
                            if let index = clips.firstIndex(of: item) { vm.selection = index }
                            openActions()
                        }
                    )
                    .frame(width: Theme.Size.clipboardListWidth)
                    Rectangle()
                        .fill(Theme.Colors.separator)
                        .frame(width: 1)
                    ClipboardPreview(item: selected)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar(showActionGroup: selected != nil)
        }
        .overlay {
            if menuOpen {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: closeMenus)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if showAppMenu {
                let content = appMenuContent
                PopoverMenu(
                    header: content.header, items: content.items, selection: $menuSelection,
                    onActivate: activateMenuItem
                )
                .padding(Self.menuInset)
                .transition(Self.menuTransition(.bottomLeading))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showActions, let content = actionsContent {
                PopoverMenu(
                    header: content.header, items: content.items, selection: $menuSelection,
                    onActivate: activateMenuItem
                )
                .padding(Self.menuInset)
                .transition(Self.menuTransition(.bottomTrailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .onChange(of: vm.focusToken) {
            searchFocused = true
            showActions = false
            showAppMenu = false
        }
        .onChange(of: vm.query) {
            vm.selection = 0
            scroll = ScrollIntent(kind: .top)
        }
        .onChange(of: vm.resetToken) {
            scroll = ScrollIntent(kind: .top)
        }
        .onChange(of: showActions) {
            if showActions {
                showAppMenu = false
                menuSelection = 0
            }
            vm.menuOpen = menuOpen
        }
        .onChange(of: showAppMenu) {
            if showAppMenu {
                showActions = false
                menuSelection = 0
            }
            vm.menuOpen = menuOpen
        }
        .onChange(of: clipFollow) { old, new in
            guard old.id != nil else { return }
            if isQueryEmpty, old.id != new.id, let id = new.id,
                let index = clips.firstIndex(where: { $0.id == id })
            {
                vm.selection = index
            }
            scroll = ScrollIntent(kind: .follow)
        }
        .onAppear { searchFocused = true }
        .onKeyPress(.downArrow) {
            if menuOpen { moveMenu(1) } else { move(1) }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if menuOpen { moveMenu(-1) } else { move(-1) }
            return .handled
        }
        .onKeyPress(keys: [.return], phases: .down) { press in
            let command = press.modifiers.contains(.command)
            if menuOpen, !command {
                activateMenuItem(menuSelection)
                return .handled
            }
            guard command, clipResults.indices.contains(selection) else { return .ignored }
            core.copyToClipboard(clipResults[selection])
            return .handled
        }
        .onKeyPress(.escape) {
            if menuOpen {
                closeMenus()
            } else {
                core.hidePalette()
            }
            return .handled
        }
        .onKeyPress(keys: [","], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            core.showSettings()
            return .handled
        }
        .onKeyPress(keys: ["k"], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            guard !clipResults.isEmpty else { return .handled }
            toggleActions()
            return .handled
        }
        .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { press in
            if menuOpen { return .handled }
            guard press.modifiers.contains(.command), clipResults.indices.contains(selection)
            else { return .ignored }
            store.remove(clipResults[selection])
            return .handled
        }
        .onKeyPress(keys: ["p"], phases: .down) { press in
            guard press.modifiers.contains(.command), clipResults.indices.contains(selection)
            else { return .ignored }
            core.togglePinnedClip(clipResults[selection])
            return .handled
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            TextField(
                "", text: $vm.query,
                prompt: Text("Type to filter entries…")
                    .foregroundStyle(Theme.Colors.textTertiary)
            )
            .textFieldStyle(.plain)
            .font(Theme.Typography.searchField)
            .tint(Color.primary)
            .focused($searchFocused)
            .onSubmit(activateSelection)
        }
        .padding(.horizontal, Theme.Spacing.md * 2)
        .frame(height: Theme.Size.headerHeight)
        .padding(.top, Theme.Size.headerPadding)
        .frame(maxWidth: .infinity)
    }

    private func bottomBar(showActionGroup: Bool) -> some View {
        HStack(spacing: 0) {
            MenuCircleButton {
                withAnimation(Self.menuAnimation) { showAppMenu.toggle() }
            }
            Spacer()
            if showActionGroup { actionGroup }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Size.bottomBarHeight)
        .frame(maxWidth: .infinity)
    }

    private var actionGroup: some View {
        HStack(spacing: 2) {
            BarButton(action: activateSelection) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(vm.pasteTarget?.pasteTitle ?? "Paste")
                        .font(Theme.Typography.bar)
                        .foregroundStyle(.primary)
                    KeyCapChip(text: "↵", style: .outline)
                }
            }
            BarButton(action: toggleActions) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Actions")
                        .font(Theme.Typography.bar)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    HStack(spacing: Theme.Spacing.xxs) {
                        KeyCapChip(text: "⌘", style: .outline)
                        KeyCapChip(text: "K", style: .outline)
                    }
                }
            }
        }
        .padding(Theme.Spacing.xs)
        .frosted(in: Capsule())
    }

    private func move(_ delta: Int) {
        guard !clipResults.isEmpty else { return }
        vm.selection = min(max(selection + delta, 0), clipResults.count - 1)
        scroll = ScrollIntent(kind: .follow)
    }

    private func moveMenu(_ delta: Int) {
        guard let count = menuContent?.items.count, count > 0 else { return }
        menuSelection = min(max(menuSelection + delta, 0), count - 1)
    }

    private func activateSelection() {
        guard clipResults.indices.contains(selection) else { return }
        core.paste(clipResults[selection])
    }

    private func openActions() {
        withAnimation(Self.menuAnimation) { showActions = true }
    }

    private func toggleActions() {
        if showActions {
            withAnimation(Self.menuAnimation) { showActions = false }
        } else {
            openActions()
        }
    }

    private func closeMenus() {
        withAnimation(Self.menuAnimation) {
            showActions = false
            showAppMenu = false
        }
    }

    private func activateMenuItem(_ index: Int) {
        guard let items = menuContent?.items, items.indices.contains(index) else { return }
        items[index].action()
        closeMenus()
    }

    private static let menuInset: CGFloat = 8
    private static let menuAnimation: Animation = .easeOut(duration: 0.14)

    private static func menuTransition(_ anchor: UnitPoint) -> AnyTransition {
        .opacity.combined(with: .scale(scale: 0.96, anchor: anchor))
    }
}

private struct ClipFollowKey: Equatable {
    let id: ClipboardItem.ID?
    let token: UUID
}

private struct MenuCircleButton: View {
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
            .background(Circle().fill(hovered ? Theme.Colors.rowHover : Color.clear))
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .frosted(in: Circle())
    }
}

private struct BarButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: 28)
                .contentShape(Capsule())
                .background(Capsule().fill(hovered ? Theme.Colors.rowHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

extension View {
    func armedHover(_ hovered: Binding<Bool>) -> some View {
        onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active: hovered.wrappedValue = AppCore.shared.palette.hoverHighlightArmed
            case .ended: hovered.wrappedValue = false
            }
        }
    }
}

struct EmptyResults: View {
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
