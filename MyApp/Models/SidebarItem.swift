import Foundation

/// A row in the Explorer-style sidebar: either a built-in favorite
/// (Home, Desktop, Documents, Downloads, ...) or a user-added location.
struct SidebarItem: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let systemImage: String
    let isUserAdded: Bool

    init(url: URL, name: String, systemImage: String, isUserAdded: Bool = false) {
        self.id = url
        self.url = url
        self.name = name
        self.systemImage = systemImage
        self.isUserAdded = isUserAdded
    }
}
