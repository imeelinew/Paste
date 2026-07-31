import AppKit
import SwiftUI

struct InstalledApplication: Identifiable, Sendable {
    let bundleID: String
    let name: String
    let path: String
    var id: String { bundleID }
}

@MainActor
final class InstalledApplications: ObservableObject {
    @Published private(set) var apps: [InstalledApplication] = []
    private var loaded = false

    func load() {
        guard !loaded else { return }
        loaded = true
        Task {
            apps = await Task.detached(priority: .utility) {
                Self.scan()
            }.value
        }
    }

    private nonisolated static func scan() -> [InstalledApplication] {
        let manager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            manager.homeDirectoryForCurrentUser.appendingPathComponent(
                "Applications", isDirectory: true),
        ]
        var byBundleID: [String: InstalledApplication] = [:]
        for root in roots {
            guard
                let urls = try? manager.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { continue }
            for url in urls where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
                    continue
                }
                let name =
                    (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                byBundleID[bundleID] = InstalledApplication(
                    bundleID: bundleID, name: name, path: url.path)
            }
        }
        return byBundleID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
