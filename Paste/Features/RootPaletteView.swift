import SwiftUI

struct RootPaletteView: View {
    @EnvironmentObject private var vm: PaletteViewModel
    @ObservedObject private var settings = AppCore.shared.settings

    @FocusState private var searchFocused: Bool
    @State private var scroll = ScrollIntent(kind: .top)

    private var isQueryEmpty: Bool {
        vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showActions: Bool {
        if case .actions = vm.overlay { return true }
        return false
    }

    private var showAppMenu: Bool { vm.overlay == .appMenu }

    @MainActor
    private var menuItems: [PopoverMenuItem] {
        vm.menuActions.map { PopoverMenuItem(action: $0, target: vm.pasteTarget) }
    }

    var body: some View {
        let clips = vm.results
        let selected = vm.selectedItem

        return Group {
            if clips.isEmpty {
                EmptyResults(
                    text: isQueryEmpty ? "Clipboard history is empty" : "No matching entries")
            } else {
                HStack(spacing: 0) {
                    ClipboardList(
                        results: clips,
                        selectedID: vm.selectedID,
                        query: vm.query,
                        scroll: scroll,
                        onSelect: { vm.select($0.id) },
                        onActions: { item in
                            withAnimation(Self.menuAnimation) {
                                vm.openActions(for: item.id)
                            }
                        }
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
        }
        .overlay {
            if vm.menuOpen {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(Self.menuAnimation) { vm.closeMenu() }
                    }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .onChange(of: vm.focusToken) {
            requestSearchFocus()
        }
        .onChange(of: vm.resetToken) {
            scroll = ScrollIntent(kind: .top)
        }
        .onChange(of: vm.followToken) {
            scroll = ScrollIntent(kind: .follow)
        }
        .onAppear {
            requestSearchFocus()
        }
        .environment(\.locale, settings.language.locale)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            TextField(
                "", text: $vm.query,
                prompt: Text("Search")
                    .foregroundStyle(Theme.Colors.textTertiary)
            )
            .textFieldStyle(.plain)
            .font(Theme.Typography.searchField)
            .tint(Color.primary)
            .focused($searchFocused)
        }
        .padding(.horizontal, Theme.Spacing.md * 2)
        .frame(height: Theme.Size.headerHeight)
        .padding(.top, Theme.Size.headerPadding)
        .frame(maxWidth: .infinity)
    }

    private func bottomBar(showActionGroup: Bool) -> some View {
        HStack(spacing: 0) {
            MenuCircleButton(pressed: showAppMenu) {
                withAnimation(Self.menuAnimation) { vm.toggleAppMenu() }
            }
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
            BarButton(
                pressed: showActions,
                action: {
                    _ = withAnimation(Self.menuAnimation) { vm.handle(.toggleActions) }
                }
            ) {
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
        withAnimation(Self.menuAnimation) { vm.activateMenuItem(at: index) }
    }

    /// `@FocusState` can remain logically true after AppKit has lost its field editor. Pulse the
    /// binding so every window-level focus request produces a fresh first-responder transition.
    private func requestSearchFocus() {
        searchFocused = false
        Task { @MainActor in
            await Task.yield()
            searchFocused = true
        }
    }

    private static let menuInset: CGFloat = 8
    private static let menuAnimation: Animation = .easeOut(duration: 0.14)

    private static func menuTransition(_ anchor: UnitPoint) -> AnyTransition {
        .opacity.combined(with: .scale(scale: 0.96, anchor: anchor))
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
                Circle().fill(
                    pressed || hovered ? Theme.Colors.selection : Color.clear
                )
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
