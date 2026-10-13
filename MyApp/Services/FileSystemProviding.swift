import Foundation

/// What a given `FileSystemProviding` backend can actually do.
///
/// Some context-menu/UI actions only make sense for a real local file (Zip,
/// Finder aliases, "Reveal in Finder") — views should check these flags
/// instead of type-checking against a concrete provider type.
/// `nonisolated`: this is a plain value type with no need for the project's
/// default main-actor isolation — without this, referencing `.local`/
/// `.remoteReadOnly` from `LocalFileSystemService` (an `actor`, not
/// `@MainActor`) is a cross-actor hop and triggers a concurrency warning.
nonisolated struct FileSystemCapabilities: Sendable {
    let supportsWrite: Bool
    let supportsZipCompress: Bool
    let supportsAlias: Bool
    let supportsRevealInFinder: Bool
    /// Gates the Properties dialog's editable Hidden/Read-only checkboxes
    /// and "Изменить значок" — these are attribute mutations in the same
    /// family as rename/delete, but remote providers can't necessarily do
    /// them (no Finder icon metadata, no `uchg` flag over SFTP).
    let supportsAttributeEditing: Bool

    static let local = FileSystemCapabilities(
        supportsWrite: true,
        supportsZipCompress: true,
        supportsAlias: true,
        supportsRevealInFinder: true,
        supportsAttributeEditing: true
    )

    /// Baseline for a remote backend (SMB-mounted shares use `.local` instead,
    /// since once mounted they're just a local path again). SFTP starts from
    /// this and enables `supportsWrite` once write operations are implemented.
    static let remoteReadOnly = FileSystemCapabilities(
        supportsWrite: false,
        supportsZipCompress: false,
        supportsAlias: false,
        supportsRevealInFinder: false,
        supportsAttributeEditing: false
    )
}

/// Abstraction over "a filesystem we can browse and mutate" — implemented by
/// `LocalFileSystemService` today, and (per the project roadmap) by an
/// SFTP-backed service later. `ExplorerViewModel` talks only to this
/// protocol, not to a concrete backend, so a window can switch what it's
/// browsing (local disk vs. a remote connection) by swapping providers.
protocol FileSystemProviding: Sendable {
    var capabilities: FileSystemCapabilities { get }

    func contents(of directoryURL: URL, showHidden: Bool) async throws -> [FileSystemItem]
    func rename(_ item: FileSystemItem, to newName: String) async throws -> URL

    /// Returns the resulting destination URL per input item, in order
    /// (after any name-collision dedup suffixing) — needed so undo/redo can
    /// know exactly what was created/moved, not just that the call succeeded.
    func copy(_ items: [FileSystemItem], into destinationDirectory: URL) async throws -> [URL]
    func move(_ items: [FileSystemItem], into destinationDirectory: URL) async throws -> [URL]

    /// Returns the trashed-item URL per input item (where available), so
    /// delete can later be undone.
    func delete(_ items: [FileSystemItem]) async throws -> [URL?]

    /// Removes items without going through the Trash — the "Delete
    /// Immediately" (⌥⌘⌫) counterpart to `delete(_:)`, matching Finder.
    /// Not undoable.
    func deletePermanently(_ items: [FileSystemItem]) async throws

    /// A direct, no-dedup move to an exact destination path — used by undo to
    /// restore an item to precisely the path it came from (unlike `move`,
    /// which auto-suffixes on a name collision; a restore should fail rather
    /// than silently land somewhere else if that exact path is occupied).
    func moveToExactDestination(_ sourceURL: URL, to destinationURL: URL) async throws

    func createFolder(in parentDirectory: URL, named baseName: String) async throws -> URL

    /// Creates an empty file, auto-suffixing on name collision
    /// ("Текстовый документ.txt", "Текстовый документ 2.txt", ...) — the
    /// context menu's "Создать" submenu counterpart to `createFolder`,
    /// matching Explorer's "New" submenu.
    func createFile(in parentDirectory: URL, named baseName: String) async throws -> URL

    /// Attribute mutations, gated by `FileSystemCapabilities.supportsAttributeEditing`.
    func setHidden(_ hidden: Bool, for items: [FileSystemItem]) async throws
    func setReadOnly(_ readOnly: Bool, for items: [FileSystemItem]) async throws

    /// Whole-file read/write, used when `copy`/`move` crosses two different
    /// providers (e.g. local <-> remote) and a native same-provider
    /// filesystem call isn't possible — the caller reads from the source
    /// provider and writes to the destination provider.
    func data(for item: FileSystemItem) async throws -> Data
    func write(_ data: Data, to destinationURL: URL) async throws
}
