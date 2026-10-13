import AppKit
import Foundation
import UniformTypeIdentifiers

/// A field by which the file list can be sorted, mirroring Windows Explorer's
/// "Details" view columns.
enum SortField: String, CaseIterable {
    case name
    case dateModified
    case type
    case size
    case dateCreated
    case path
}

/// Named `ItemSortOrder` (not `SortOrder`) to avoid colliding with the
/// Swift standard library's `SortOrder`, which `KeyPathComparator` uses.
enum ItemSortOrder {
    case forward
    case reverse
}

/// A single file or folder shown in the file list / sidebar.
///
/// Identity is intentionally the `url`, not the `name`: renaming an item must
/// not change its identity, or SwiftUI will lose row state (selection, the
/// in-place rename `TextField`'s focus) mid-edit.
///
/// `nonisolated`: a plain value type shouldn't inherit the project's default
/// main-actor isolation — without this, building instances inside
/// `LocalFileSystemService` (an `actor`) is a cross-actor hop through its
/// memberwise init. The `icon` property below stays explicitly `@MainActor`
/// since it calls `NSWorkspace`, which does need it.
nonisolated struct FileSystemItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let fileSize: Int64?
    let contentModificationDate: Date?
    let contentCreationDate: Date?
    let contentType: UTType?
    let isHidden: Bool

    var id: URL { url }

    /// Loads a single item's metadata from disk.
    init(url: URL) {
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .contentTypeKey,
            .isHiddenKey,
            .nameKey,
        ])

        self.url = url
        self.name = values?.name ?? url.lastPathComponent
        self.isDirectory = values?.isDirectory ?? false
        self.fileSize = values?.fileSize.map(Int64.init)
        self.contentModificationDate = values?.contentModificationDate
        self.contentCreationDate = values?.creationDate
        self.contentType = values?.contentType
        self.isHidden = values?.isHidden ?? false
    }

    /// Builds an item directly from pre-fetched resource values, avoiding a
    /// second disk round-trip when enumerating a directory in bulk.
    init(
        url: URL,
        name: String,
        isDirectory: Bool,
        fileSize: Int64?,
        contentModificationDate: Date?,
        contentCreationDate: Date? = nil,
        contentType: UTType?,
        isHidden: Bool
    ) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.fileSize = fileSize
        self.contentModificationDate = contentModificationDate
        self.contentCreationDate = contentCreationDate
        self.contentType = contentType
        self.isHidden = isHidden
    }

    /// The system icon for this item, as shown by Finder/Explorer-style file
    /// lists. `icon(forFile:)` needs a real file on disk, which only exists
    /// for local (`file://`) URLs — a remote item (e.g. a future SFTP
    /// listing, per the project roadmap) falls back to a UTI-based generic
    /// icon that doesn't require the file to actually be present locally.
    @MainActor
    var icon: NSImage {
        guard url.isFileURL else {
            return NSWorkspace.shared.icon(for: isDirectory ? .folder : (contentType ?? .data))
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Short, human readable type description (e.g. "Folder", "PDF Document").
    var typeDescription: String {
        if isDirectory {
            return "Папка"
        }
        return contentType?.localizedDescription?.capitalized ?? "Файл"
    }

    /// Non-optional stand-ins for `contentModificationDate`/`fileSize`, used
    /// with `KeyPathComparator` for the Table's clickable column headers
    /// (`KeyPathComparator` requires `Comparable`, which `Date?`/`Int64?`
    /// are not).
    var sortableModificationDate: Date { contentModificationDate ?? .distantPast }
    var sortableCreationDate: Date { contentCreationDate ?? .distantPast }
    var sortableSize: Int64 { fileSize ?? 0 }
    var sortablePath: String { url.isFileURL ? url.path : url.absoluteString }

    static func == (lhs: FileSystemItem, rhs: FileSystemItem) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
