import AppKit
import Foundation
import Observation

/// Owns navigation state (current folder, back/forward history), the sorted
/// item list for the current folder, selection, and the clipboard used for
/// cut/copy/paste — the single source of truth for one Explorer *tab*.
/// `Identifiable` so `ExplorerWindowModel` can hold several of these as tabs.
@Observable
@MainActor
final class ExplorerViewModel: Identifiable {
    let id = UUID()
    private(set) var currentDirectoryURL: URL
    private(set) var items: [FileSystemItem] = []
    private(set) var isLoading = false

    var sortField: SortField = .name {
        didSet { resort() }
    }
    var sortOrder: ItemSortOrder = .forward {
        didSet { resort() }
    }
    var showHidden = false {
        didSet { Task { await reload() } }
    }

    /// Filters `items` by name (case/diacritic-insensitive substring match),
    /// bound to a `.searchable()` field. Empty string shows everything.
    var searchQuery: String = "" {
        didSet { resort() }
    }

    var selection: Set<FileSystemItem.ID> = []
    var activeError: FileOperationError?
    var renamingItemID: FileSystemItem.ID?

    /// Which item(s) the "Свойства" sheet is showing, `nil` when closed.
    var propertiesTarget: PropertiesTarget?

    /// Items awaiting confirmation for "Delete Immediately" (⌥⌘⌫) — `nil`
    /// when no confirmation alert is showing.
    var pendingPermanentDelete: [FileSystemItem]?

    var selectedItems: [FileSystemItem] {
        items.filter { selection.contains($0.id) }
    }

    /// Bumped after a successful icon change — `FileSystemItem` compares
    /// equal by `url` alone, so a `reload()` after `setCustomIcon` produces
    /// an identical-looking item and SwiftUI has no other signal to redraw
    /// the row's icon. Views that show icons apply `.id(iconRevision)`.
    private(set) var iconRevision = 0

    let metadataService = FileMetadataService()

    /// Set by `ExplorerView` from `@Environment(\.undoManager)`. `weak`
    /// since the window (not this view model) owns the undo manager's
    /// lifetime. File operations register inverses here; when `nil` (e.g.
    /// briefly before the view appears), operations simply aren't undoable.
    weak var undoManager: UndoManager?

    /// Which optional columns `FileListView` shows, persisted across
    /// launches — matches Explorer's "Choose columns".
    var visibleColumns: Set<FileListColumn> {
        didSet { Self.persistVisibleColumns(visibleColumns) }
    }

    /// Items staged for a cut/copy, plus whether the pending operation is a
    /// cut (move) rather than a copy.
    private(set) var pendingURLs: [URL] = []
    private(set) var isCutOperation = false

    private var backStack: [URL] = []
    private var forwardStack: [URL] = []

    /// `var`, not `let`: selecting a remote connection in the sidebar swaps
    /// the active provider for this window (per the project roadmap — local
    /// disk vs. an SMB-mounted share vs. an SFTP connection are all just
    /// different `FileSystemProviding` values).
    private var service: any FileSystemProviding
    private var unsortedItems: [FileSystemItem] = []

    private static let visibleColumnsDefaultsKey = "ExplorerMacOS.visibleColumns"

    // `service` defaults to `nil` and `LocalFileSystemService()` is
    // constructed in the body, not as a default parameter value: Swift
    // evaluates default-argument expressions in a nonisolated context
    // regardless of the enclosing type's own actor isolation, which made a
    // directly-defaulted `= LocalFileSystemService()` trip a concurrency
    // warning. Constructing it inside the (MainActor-isolated) init body
    // avoids that.
    init(startingAt url: URL, service: (any FileSystemProviding)? = nil) {
        self.currentDirectoryURL = url
        self.service = service ?? LocalFileSystemService()
        self.visibleColumns = Self.loadVisibleColumns()
    }

    private static func loadVisibleColumns() -> Set<FileListColumn> {
        guard let rawValues = UserDefaults.standard.array(forKey: visibleColumnsDefaultsKey) as? [String] else {
            return FileListColumn.defaultVisible
        }
        return Set(rawValues.compactMap(FileListColumn.init(rawValue:)))
    }

    private static func persistVisibleColumns(_ columns: Set<FileListColumn>) {
        UserDefaults.standard.set(columns.map(\.rawValue), forKey: visibleColumnsDefaultsKey)
    }

    /// Exposes what the active provider can do, so views can gate
    /// provider-specific actions (Zip, Alias, Reveal in Finder) without
    /// type-checking the concrete `service` instance.
    var providerCapabilities: FileSystemCapabilities { service.capabilities }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { currentDirectoryURL.pathComponents.count > 1 }

    /// For the status bar: count + combined size of the current selection,
    /// `nil` when nothing is selected (status bar falls back to the total
    /// item count in that case).
    var selectionSummary: (count: Int, totalSize: Int64)? {
        guard !selection.isEmpty else { return nil }
        let selectedItems = items.filter { selection.contains($0.id) }
        let totalSize = selectedItems.reduce(Int64(0)) { $0 + ($1.fileSize ?? 0) }
        return (selectedItems.count, totalSize)
    }

    // MARK: - Navigation

    func navigate(to url: URL, recordHistory: Bool = true) {
        guard url != currentDirectoryURL else { return }
        if recordHistory {
            backStack.append(currentDirectoryURL)
            forwardStack.removeAll()
        }
        currentDirectoryURL = url
        selection.removeAll()
        Task { await reload() }
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(currentDirectoryURL)
        currentDirectoryURL = previous
        selection.removeAll()
        Task { await reload() }
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentDirectoryURL)
        currentDirectoryURL = next
        selection.removeAll()
        Task { await reload() }
    }

    func goUp() {
        let parent = currentDirectoryURL.deletingLastPathComponent()
        guard parent != currentDirectoryURL else { return }
        navigate(to: parent)
    }

    /// Subfolders of `url`, for the breadcrumb's chevron dropdown — lets the
    /// user jump straight into a sibling of the current path without fully
    /// navigating through the intermediate segment first, matching
    /// Explorer's address-bar chevron menus.
    func subfolders(of url: URL) async -> [FileSystemItem] {
        let contents = (try? await service.contents(of: url, showHidden: showHidden)) ?? []
        return contents
            .filter(\.isDirectory)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Remote connections

    /// Switches this window to browse a remote connection — mounts the SMB
    /// share (reusing `LocalFileSystemService` once mounted, per the
    /// roadmap) or, for SFTP, reports that the backend isn't wired up yet
    /// (it needs the Citadel SPM package added in Xcode first; see the
    /// `SFTPFileSystemService` placeholder). Returns whether it succeeded,
    /// so the caller (the "Connect to Server" sheet) knows whether to
    /// dismiss or show the error inline.
    func connect(to connection: RemoteConnection, password: String) async -> Bool {
        switch connection.protocolKind {
        case .smb:
            do {
                let mountedURL = try await SMBMountService().mount(connection: connection, password: password)
                service = LocalFileSystemService()
                currentDirectoryURL = mountedURL
                backStack.removeAll()
                forwardStack.removeAll()
                selection.removeAll()
                await reload()
                return true
            } catch {
                activeError = .underlying(error)
                return false
            }
        case .sftp:
            activeError = .underlying(SFTPNotYetAvailableError())
            return false
        }
    }

    // MARK: - Loading

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            unsortedItems = try await service.contents(of: currentDirectoryURL, showHidden: showHidden)
            resort()
        } catch let error as FileOperationError {
            activeError = error
        } catch {
            activeError = .underlying(error)
        }
    }

    private func resort() {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmedQuery.isEmpty
            ? unsortedItems
            : unsortedItems.filter { $0.name.localizedStandardContains(trimmedQuery) }

        items = filtered.sorted { lhs, rhs in
            // Folders before files, matching Explorer's default grouping.
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            let result: Bool
            switch sortField {
            case .name:
                result = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .dateModified:
                result = (lhs.contentModificationDate ?? .distantPast) < (rhs.contentModificationDate ?? .distantPast)
            case .type:
                result = lhs.typeDescription.localizedStandardCompare(rhs.typeDescription) == .orderedAscending
            case .size:
                result = (lhs.fileSize ?? 0) < (rhs.fileSize ?? 0)
            case .dateCreated:
                result = (lhs.contentCreationDate ?? .distantPast) < (rhs.contentCreationDate ?? .distantPast)
            case .path:
                result = lhs.sortablePath.localizedStandardCompare(rhs.sortablePath) == .orderedAscending
            }
            return sortOrder == .forward ? result : !result
        }
    }

    // MARK: - Undo/redo

    /// Registers `handler` as the next undo (or, if called from inside an
    /// undo handler, the next redo) step — `UndoManager`'s own mechanism
    /// turns a `registerUndo` call made *during* an undo into the matching
    /// redo automatically, which is what lets every operation below chain
    /// indefinitely in both directions with a single recursive call back
    /// into its own "do the opposite" method.
    private func registerUndo(_ actionName: String, _ handler: @escaping () async -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { _ in
            Task { @MainActor in
                await handler()
            }
        }
        undoManager.setActionName(actionName)
    }

    // MARK: - File operations

    func createFolder() async {
        do {
            let newURL = try await service.createFolder(in: currentDirectoryURL, named: "Новая папка")
            await reload()
            selection = [newURL]
            renamingItemID = newURL
            registerCreateFolderUndo(at: newURL)
        } catch let error as FileOperationError {
            activeError = error
        } catch {
            activeError = .underlying(error)
        }
    }

    private func registerCreateFolderUndo(at url: URL) {
        registerUndo("Новая папка") { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.service.delete([FileSystemItem(url: url)])
                await self.reload()
                self.registerCreateFolderRedo(parent: url.deletingLastPathComponent(), name: url.lastPathComponent)
            } catch {
                self.activeError = .underlying(error)
            }
        }
    }

    private func registerCreateFolderRedo(parent: URL, name: String) {
        registerUndo("Новая папка") { [weak self] in
            guard let self else { return }
            do {
                let newURL = try await self.service.createFolder(in: parent, named: name)
                await self.reload()
                self.registerCreateFolderUndo(at: newURL)
            } catch {
                self.activeError = .underlying(error)
            }
        }
    }

    /// Creates an empty file named `baseName` (including extension, e.g.
    /// "Текстовый документ.txt") — the "Создать" submenu's file-type entries.
    func createFile(named baseName: String) async {
        do {
            let newURL = try await service.createFile(in: currentDirectoryURL, named: baseName)
            await reload()
            selection = [newURL]
            renamingItemID = newURL
            registerCreateFileUndo(at: newURL)
        } catch let error as FileOperationError {
            activeError = error
        } catch {
            activeError = .underlying(error)
        }
    }

    private func registerCreateFileUndo(at url: URL) {
        registerUndo("Новый файл") { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.service.delete([FileSystemItem(url: url)])
                await self.reload()
                self.registerCreateFileRedo(parent: url.deletingLastPathComponent(), name: url.lastPathComponent)
            } catch {
                self.activeError = .underlying(error)
            }
        }
    }

    private func registerCreateFileRedo(parent: URL, name: String) {
        registerUndo("Новый файл") { [weak self] in
            guard let self else { return }
            do {
                let newURL = try await self.service.createFile(in: parent, named: name)
                await self.reload()
                self.registerCreateFileUndo(at: newURL)
            } catch {
                self.activeError = .underlying(error)
            }
        }
    }

    func rename(_ item: FileSystemItem, to newName: String) async {
        do {
            let newURL = try await service.rename(item, to: newName)
            await reload()
            registerRenameUndo(currentURL: newURL, previousName: item.name)
        } catch let error as FileOperationError {
            activeError = error
        } catch {
            activeError = .underlying(error)
        }
        renamingItemID = nil
    }

    /// Renaming back and forth is symmetric, so a single recursive helper
    /// covers both undo and redo — undoing "rename to X" is "rename to the
    /// previous name", and redoing that is "rename to X" again.
    private func registerRenameUndo(currentURL: URL, previousName: String) {
        registerUndo("Переименование") { [weak self] in
            guard let self else { return }
            do {
                let revertedItem = FileSystemItem(url: currentURL)
                let restoredURL = try await self.service.rename(revertedItem, to: previousName)
                await self.reload()
                self.registerRenameUndo(currentURL: restoredURL, previousName: currentURL.lastPathComponent)
            } catch {
                self.activeError = .underlying(error)
            }
        }
    }

    func delete(_ itemsToDelete: [FileSystemItem]) async {
        do {
            let trashedURLs = try await service.delete(itemsToDelete)
            await reload()
            let restorations = zip(itemsToDelete, trashedURLs).compactMap { item, trashedURL in
                trashedURL.map { (trashed: $0, original: item.url) }
            }
            if !restorations.isEmpty {
                registerDeleteUndo(restorations: restorations)
            }
        } catch let error as FileOperationError {
            activeError = error
        } catch {
            activeError = .underlying(error)
        }
    }

    /// Shows the "Delete Immediately" confirmation alert, matching Finder's
    /// ⌥⌘⌫ behavior.
    func requestPermanentDelete(_ itemsToDelete: [FileSystemItem]) {
        guard !itemsToDelete.isEmpty else { return }
        pendingPermanentDelete = itemsToDelete
    }

    /// Permanently removes the items pending confirmation. Not undoable —
    /// unlike `delete(_:)`, there's no Trash to restore from.
    func confirmPermanentDelete() async {
        guard let itemsToDelete = pendingPermanentDelete else { return }
        pendingPermanentDelete = nil
        do {
            try await service.deletePermanently(itemsToDelete)
            await reload()
        } catch let error as FileOperationError {
            activeError = error
        } catch {
            activeError = .underlying(error)
        }
    }

    private func registerDeleteUndo(restorations: [(trashed: URL, original: URL)]) {
        registerUndo("Удаление") { [weak self] in
            guard let self else { return }
            do {
                for pair in restorations {
                    try await self.service.moveToExactDestination(pair.trashed, to: pair.original)
                }
                await self.reload()
                let restoredItems = restorations.map { FileSystemItem(url: $0.original) }
                self.registerDeleteRedo(items: restoredItems)
            } catch {
                self.activeError = .underlying(error)
            }
        }
    }

    private func registerDeleteRedo(items: [FileSystemItem]) {
        registerUndo("Удаление") { [weak self] in
            guard let self else { return }
            do {
                let trashedURLs = try await self.service.delete(items)
                await self.reload()
                let restorations = zip(items, trashedURLs).compactMap { item, trashedURL in
                    trashedURL.map { (trashed: $0, original: item.url) }
                }
                if !restorations.isEmpty {
                    self.registerDeleteUndo(restorations: restorations)
                }
            } catch {
                self.activeError = .underlying(error)
            }
        }
    }

    // MARK: - Properties dialog enrichment (local-only, read-only)

    func attributes(for item: FileSystemItem) async -> ItemAttributes {
        await metadataService.attributes(for: item.url, isDirectory: item.isDirectory)
    }

    func spotlightMetadata(for item: FileSystemItem) async -> [ExtendedMetadataValue] {
        guard item.url.isFileURL else { return [] }
        return await metadataService.spotlightMetadata(for: item.url)
    }

    /// Recursive size/item-count walk for one or more folders — the stream
    /// is cancelled automatically when the consuming `.task` is cancelled
    /// (e.g. the Properties sheet closing).
    func folderStatisticsStream(for items: [FileSystemItem]) -> AsyncThrowingStream<FolderStatistics, Error> {
        metadataService.folderStatistics(for: items.map(\.url))
    }

    // MARK: - Attribute editing (local-only; gated by `providerCapabilities`)

    func setHidden(_ hidden: Bool, for itemsToChange: [FileSystemItem]) async {
        guard providerCapabilities.supportsAttributeEditing, !itemsToChange.isEmpty else { return }
        do {
            try await service.setHidden(hidden, for: itemsToChange)
            await reload()
            registerUndo(hidden ? "Скрытие" : "Отмена скрытия") { [weak self] in
                await self?.setHidden(!hidden, for: itemsToChange)
            }
        } catch let error as FileOperationError {
            activeError = error
        } catch {
            activeError = .underlying(error)
        }
    }

    func setReadOnly(_ readOnly: Bool, for itemsToChange: [FileSystemItem]) async {
        guard providerCapabilities.supportsAttributeEditing, !itemsToChange.isEmpty else { return }
        do {
            try await service.setReadOnly(readOnly, for: itemsToChange)
            await reload()
            registerUndo(readOnly ? "Блокировка" : "Снятие блокировки") { [weak self] in
                await self?.setReadOnly(!readOnly, for: itemsToChange)
            }
        } catch let error as FileOperationError {
            activeError = error
        } catch {
            activeError = .underlying(error)
        }
    }

    /// Sets (or clears, passing `nil`) a custom Finder icon for `item`.
    /// Side-channel Finder metadata, not a content mutation — no
    /// `FileSystemProviding` method needed, same reasoning as Zip/Alias.
    func setCustomIcon(_ image: NSImage?, for item: FileSystemItem) {
        guard providerCapabilities.supportsAttributeEditing, item.url.isFileURL else { return }
        let success = NSWorkspace.shared.setIcon(image, forFile: item.url.path, options: [])
        if success {
            iconRevision += 1
        } else {
            activeError = .underlying(
                NSError(domain: "ExplorerMacOS.Icon", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Не удалось изменить значок."
                ])
            )
        }
    }

    // MARK: - Zip / Alias (local-only; gated by `providerCapabilities`)

    func compressToZip(_ itemsToCompress: [FileSystemItem]) async {
        guard providerCapabilities.supportsZipCompress, !itemsToCompress.isEmpty else { return }

        let baseName = itemsToCompress.count == 1 ? itemsToCompress[0].name : "Архив"
        var destination = currentDirectoryURL.appendingPathComponent("\(baseName).zip")
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = currentDirectoryURL.appendingPathComponent("\(baseName) \(suffix).zip")
            suffix += 1
        }

        do {
            try await ZipService.compress(itemsToCompress.map(\.url), into: destination)
            await reload()
        } catch {
            activeError = .underlying(error)
        }
    }

    func createAlias(for item: FileSystemItem) async {
        guard providerCapabilities.supportsAlias else { return }
        do {
            _ = try AliasService.createAlias(for: item, in: currentDirectoryURL)
            await reload()
        } catch {
            activeError = .underlying(error)
        }
    }

    // MARK: - Clipboard (cut/copy/paste)

    func markForCopy(_ urls: [URL]) {
        pendingURLs = urls
        isCutOperation = false
    }

    func markForCut(_ urls: [URL]) {
        pendingURLs = urls
        isCutOperation = true
    }

    func pasteIntoCurrentDirectory() async {
        guard !pendingURLs.isEmpty else { return }
        let targets = items.filter { pendingURLs.contains($0.url) } + pendingURLs
            .filter { url in !items.contains { $0.url == url } }
            .map { FileSystemItem(url: $0) }

        do {
            if isCutOperation {
                let destinationURLs = try await service.move(targets, into: currentDirectoryURL)
                pendingURLs = []
                await reload()
                registerMoveUndo(sourceItems: targets, destinationURLs: destinationURLs)
            } else {
                let destinationURLs = try await service.copy(targets, into: currentDirectoryURL)
                await reload()
                registerCopyUndo(sourceItems: targets, destinationDirectory: currentDirectoryURL, destinationURLs: destinationURLs)
            }
        } catch let error as FileOperationError {
            activeError = error
        } catch {
            activeError = .underlying(error)
        }
    }

    /// Moves or copies arbitrary URLs straight into `destination`, regardless
    /// of the clipboard state — used when files are dropped directly onto a
    /// sidebar folder rather than pasted into the current directory.
    func moveOrCopy(_ urls: [URL], into destination: URL, asCopy: Bool) async {
        let targets = urls.map { FileSystemItem(url: $0) }
        do {
            if asCopy {
                let destinationURLs = try await service.copy(targets, into: destination)
                if destination == currentDirectoryURL {
                    await reload()
                }
                registerCopyUndo(sourceItems: targets, destinationDirectory: destination, destinationURLs: destinationURLs)
            } else {
                let destinationURLs = try await service.move(targets, into: destination)
                if destination == currentDirectoryURL {
                    await reload()
                }
                registerMoveUndo(sourceItems: targets, destinationURLs: destinationURLs)
            }
        } catch let error as FileOperationError {
            activeError = error
        } catch {
            activeError = .underlying(error)
        }
    }

    // MARK: - Copy/move undo-redo

    private func registerCopyUndo(sourceItems: [FileSystemItem], destinationDirectory: URL, destinationURLs: [URL]) {
        registerUndo("Копирование") { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.service.delete(destinationURLs.map { FileSystemItem(url: $0) })
                await self.reload()
                self.registerCopyRedo(sourceItems: sourceItems, destinationDirectory: destinationDirectory)
            } catch {
                self.activeError = .underlying(error)
            }
        }
    }

    private func registerCopyRedo(sourceItems: [FileSystemItem], destinationDirectory: URL) {
        registerUndo("Копирование") { [weak self] in
            guard let self else { return }
            do {
                let destinationURLs = try await self.service.copy(sourceItems, into: destinationDirectory)
                await self.reload()
                self.registerCopyUndo(sourceItems: sourceItems, destinationDirectory: destinationDirectory, destinationURLs: destinationURLs)
            } catch {
                self.activeError = .underlying(error)
            }
        }
    }

    /// `sourceItems` hold the *original* URLs (before the move); restoring on
    /// undo uses `moveToExactDestination` so the item lands back at exactly
    /// the path it started at, rather than a dedup-suffixed name.
    private func registerMoveUndo(sourceItems: [FileSystemItem], destinationURLs: [URL]) {
        registerUndo("Перемещение") { [weak self] in
            guard let self else { return }
            do {
                for (destinationURL, sourceItem) in zip(destinationURLs, sourceItems) {
                    try await self.service.moveToExactDestination(destinationURL, to: sourceItem.url)
                }
                await self.reload()
                guard let destinationDirectory = destinationURLs.first?.deletingLastPathComponent() else { return }
                self.registerMoveRedo(sourceItems: sourceItems, destinationDirectory: destinationDirectory)
            } catch {
                self.activeError = .underlying(error)
            }
        }
    }

    private func registerMoveRedo(sourceItems: [FileSystemItem], destinationDirectory: URL) {
        registerUndo("Перемещение") { [weak self] in
            guard let self else { return }
            do {
                let destinationURLs = try await self.service.move(sourceItems, into: destinationDirectory)
                await self.reload()
                self.registerMoveUndo(sourceItems: sourceItems, destinationURLs: destinationURLs)
            } catch {
                self.activeError = .underlying(error)
            }
        }
    }
}
