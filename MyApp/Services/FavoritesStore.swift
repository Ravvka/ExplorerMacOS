import Foundation
import Observation

/// Persists the list of user-added sidebar locations ("Разделы").
///
/// Since the app does not run inside the App Sandbox, plain paths are
/// sufficient — there is no need for security-scoped bookmarks.
@Observable
@MainActor
final class FavoritesStore {
    private static let defaultsKey = "ExplorerMacOS.userFavoritePaths"
    private let userDefaults: UserDefaults

    private(set) var items: [SidebarItem] = []

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        load()
    }

    func add(url: URL) {
        guard !items.contains(where: { $0.url == url }) else { return }
        items.append(SidebarItem(url: url, name: url.lastPathComponent, systemImage: "folder", isUserAdded: true))
        persist()
    }

    func remove(url: URL) {
        items.removeAll { $0.url == url }
        persist()
    }

    private func load() {
        guard let paths = userDefaults.stringArray(forKey: Self.defaultsKey) else { return }
        items = paths.map { path in
            let url = URL(fileURLWithPath: path)
            return SidebarItem(url: url, name: url.lastPathComponent, systemImage: "folder", isUserAdded: true)
        }
    }

    private func persist() {
        let paths = items.map(\.url.path)
        userDefaults.set(paths, forKey: Self.defaultsKey)
    }
}
