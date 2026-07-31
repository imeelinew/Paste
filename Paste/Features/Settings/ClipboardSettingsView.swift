import SwiftUI

struct ClipboardSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @EnvironmentObject private var installedApplications: InstalledApplications
    @State private var confirmingClear = false
    @State private var showingAppPicker = false

    var body: some View {
        SettingsPane(
            title: "Clipboard",
            subtitle: "Control how much history Paste keeps and which apps are recorded."
        ) {
            SettingsCard(header: "Shortcut") {
                SettingsRow(
                    title: "Clipboard History",
                    subtitle: "Open the clipboard history browser.",
                    systemImage: "doc.on.clipboard",
                    tint: .orange
                ) {
                    ShortcutRecorder(action: .toggleClipboard)
                }
            }

            SettingsCard(header: "History") {
                SettingsRow(
                    title: "Keep history for",
                    subtitle: "Entries older than this are deleted automatically.",
                    systemImage: "clock.arrow.circlepath",
                    tint: .orange
                ) {
                    Picker("", selection: $settings.clipboardRetention) {
                        ForEach(ClipboardRetention.allCases) { retention in
                            Text(retention.title).tag(retention)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: settings.clipboardRetention) {
                        let store = AppCore.shared.clipboardStore
                        store.maxAge = settings.clipboardRetention.maxAge
                        store.enforceLimits()
                    }
                }
            }

            SettingsCard(header: "Disabled Applications") {
                ForEach(settings.clipboardDisabledApps, id: \.self) { bundleID in
                    DisabledAppRow(bundleID: bundleID) {
                        settings.clipboardDisabledApps.removeAll { $0 == bundleID }
                    }
                    SettingsDivider()
                }

                HStack(spacing: Theme.Spacing.lg) {
                    Text("Clipboard changes from these apps won't be recorded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: Theme.Spacing.xl)
                    Button {
                        showingAppPicker = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showingAppPicker, arrowEdge: .bottom) {
                        AppPickerPopover(excluded: Set(settings.clipboardDisabledApps)) {
                            bundleID in
                            settings.clipboardDisabledApps.append(bundleID)
                            showingAppPicker = false
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.md)
            }

            SettingsCard(header: "Danger Zone") {
                SettingsRow(
                    title: "Clear history",
                    subtitle: "Permanently remove every saved clip and image.",
                    systemImage: "trash",
                    tint: .red
                ) {
                    Button("Clear…", role: .destructive) { confirmingClear = true }
                        .controlSize(.regular)
                }
            }
        }
        .task { installedApplications.load() }
        .confirmationDialog(
            "Clear clipboard history?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                AppCore.shared.clipboardStore.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }
}

private struct DisabledAppRow: View {
    let bundleID: String
    let onRemove: () -> Void
    @EnvironmentObject private var installedApplications: InstalledApplications

    var body: some View {
        let app = installedApplications.apps.first { $0.bundleID == bundleID }
        let path = app?.path
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
        HStack(spacing: Theme.Spacing.lg) {
            Image(nsImage: path.map(IconCache.icon(forFile:)) ?? genericIcon)
                .resizable()
                .frame(width: 22, height: 22)
            Text(app?.name ?? bundleID)
                .font(.body)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.xl)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    private var genericIcon: NSImage {
        NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

private struct AppPickerPopover: View {
    let excluded: Set<String>
    let onSelect: (String) -> Void
    @EnvironmentObject private var installedApplications: InstalledApplications
    @State private var query = ""

    private var candidates: [InstalledApplication] {
        installedApplications.apps.filter {
            !excluded.contains($0.bundleID)
                && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search apps…", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(Theme.Spacing.md)
            Divider()
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(candidates) { app in
                        Button { onSelect(app.bundleID) } label: {
                            HStack(spacing: Theme.Spacing.lg) {
                                Image(nsImage: IconCache.icon(forFile: app.path))
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text(app.name).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.Spacing.sm)
            }
        }
        .frame(width: 280, height: 320)
    }
}
