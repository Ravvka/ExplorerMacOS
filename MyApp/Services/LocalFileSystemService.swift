import Foundation
import UniformTypeIdentifiers

/// Errors surfaced by `FileSystemProviding` implementations, suitable for
/// display in an `.alert`.
enum FileOperationError: LocalizedError {
    case nameAlreadyExists(String)
    case permissionDenied
    case notFound
    case invalidName
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .nameAlreadyExists(let name):
            return "Элемент с именем «\(name)» уже существует."
        case .permissionDenied:
            return "Нет доступа для выполнения этой операции."
        case .notFound:
            return "Файл или папка не найдены."
        case .invalidName:
            return "Недопустимое имя."
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}

/// Wraps `FileManager` file operations behind `async`/`await`, off the main
/// actor, so directory listings and file I/O never block the UI.
///
/// Conforms to `FileSystemProviding` so `ExplorerViewModel` can treat this
/// the same way it treats a future remote (SFTP) backend. An SMB share
/// mounted via `NetFSMountURLAsync` becomes a normal local path once
/// mounted, so it also goes through this same service — no separate SMB
/// provider is needed.
actor LocalFileSystemService: FileSystemProviding {
    nonisolated let capabilities = FileSystemCapabilities.local

    private let fileManager = FileManager.default

    /// Lists the contents of a directory, batching the resource-value fetch
    /// for every entry into the single `contentsOfDirectory` call instead of
    /// stat-ing each file individually.
    func contents(of directoryURL: URL, showHidden: Bool) throws -> [FileSystemItem] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .contentTypeKey,
            .isHiddenKey,
            .nameKey,
        ]

        var options: FileManager.DirectoryEnumerationOptions = []
        if !showHidden {
            options.insert(.skipsHiddenFiles)
        }

        do {
            let urls = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: keys,
                options: options
            )

            return urls.map { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return FileSystemItem(
                    url: url,
                    name: values?.name ?? url.lastPathComponent,
                    isDirectory: values?.isDirectory ?? false,
                    fileSize: values?.fileSize.map(Int64.init),
                    contentModificationDate: values?.contentModificationDate,
                    contentCreationDate: values?.creationDate,
                    contentType: values?.contentType,
                    isHidden: values?.isHidden ?? false
                )
            }
        } catch {
            throw Self.mapError(error)
        }
    }

    func rename(_ item: FileSystemItem, to newName: String) throws -> URL {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            throw FileOperationError.invalidName
        }

        let destination = item.url.deletingLastPathComponent().appendingPathComponent(trimmed)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw FileOperationError.nameAlreadyExists(trimmed)
        }

        do {
            try fileManager.moveItem(at: item.url, to: destination)
            return destination
        } catch {
            throw Self.mapError(error)
        }
    }

    func copy(_ items: [FileSystemItem], into destinationDirectory: URL) throws -> [URL] {
        var results: [URL] = []
        for item in items {
            let destination = uniqueDestination(for: item.url, in: destinationDirectory)
            do {
                try fileManager.copyItem(at: item.url, to: destination)
                results.append(destination)
            } catch {
                throw Self.mapError(error)
            }
        }
        return results
    }

    func move(_ items: [FileSystemItem], into destinationDirectory: URL) throws -> [URL] {
        var results: [URL] = []
        for item in items {
            let destination = uniqueDestination(for: item.url, in: destinationDirectory)
            do {
                try fileManager.moveItem(at: item.url, to: destination)
                results.append(destination)
            } catch {
                throw Self.mapError(error)
            }
        }
        return results
    }

    /// Direct, no-dedup move to an exact path — used to restore an item to
    /// precisely where it came from (see protocol doc).
    func moveToExactDestination(_ sourceURL: URL, to destinationURL: URL) throws {
        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            throw Self.mapError(error)
        }
    }

    /// Sends items to the Trash, matching Explorer's default (Recycle Bin)
    /// delete semantics rather than a permanent delete. Returns the
    /// resulting trashed-item URL per input item (where the system reports
    /// one), so a future undo-of-delete has something to restore.
    func delete(_ items: [FileSystemItem]) throws -> [URL?] {
        var results: [URL?] = []
        for item in items {
            do {
                var resultingURL: NSURL?
                try fileManager.trashItem(at: item.url, resultingItemURL: &resultingURL)
                results.append(resultingURL as URL?)
            } catch {
                throw Self.mapError(error)
            }
        }
        return results
    }

    /// Removes items directly, bypassing the Trash entirely — the
    /// "Delete Immediately" counterpart to `delete(_:)`.
    func deletePermanently(_ items: [FileSystemItem]) throws {
        for item in items {
            do {
                try fileManager.removeItem(at: item.url)
            } catch {
                throw Self.mapError(error)
            }
        }
    }

    /// Reads a file's entire contents — used when `copy`/`move` crosses two
    /// different providers and a native same-provider filesystem call isn't
    /// possible.
    func data(for item: FileSystemItem) throws -> Data {
        do {
            return try Data(contentsOf: item.url)
        } catch {
            throw Self.mapError(error)
        }
    }

    /// Writes `data` as a new file at `destinationURL` — the write side of
    /// cross-provider transfers.
    func write(_ data: Data, to destinationURL: URL) throws {
        do {
            try data.write(to: destinationURL, options: .atomic)
        } catch {
            throw Self.mapError(error)
        }
    }

    /// Creates a new folder, auto-suffixing on name collision
    /// ("Новая папка", "Новая папка 2", ...), mirroring Explorer's idiom.
    func createFolder(in parentDirectory: URL, named baseName: String = "Новая папка") throws -> URL {
        var candidate = parentDirectory.appendingPathComponent(baseName)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = parentDirectory.appendingPathComponent("\(baseName) \(suffix)")
            suffix += 1
        }

        do {
            try fileManager.createDirectory(at: candidate, withIntermediateDirectories: false)
            return candidate
        } catch {
            throw Self.mapError(error)
        }
    }

    /// Creates an empty file, auto-suffixing on name collision the same way
    /// `createFolder` does, but preserving `baseName`'s extension.
    func createFile(in parentDirectory: URL, named baseName: String) throws -> URL {
        let ext = (baseName as NSString).pathExtension
        let stem = (baseName as NSString).deletingPathExtension

        var candidate = parentDirectory.appendingPathComponent(baseName)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(ext)"
            candidate = parentDirectory.appendingPathComponent(name)
            suffix += 1
        }

        guard fileManager.createFile(atPath: candidate.path, contents: Data()) else {
            throw FileOperationError.permissionDenied
        }
        return candidate
    }

    /// Sets/clears the hidden flag via the standard resource-value setter.
    func setHidden(_ hidden: Bool, for items: [FileSystemItem]) throws {
        for item in items {
            var url = item.url
            var values = URLResourceValues()
            values.isHidden = hidden
            do {
                try url.setResourceValues(values)
            } catch {
                throw Self.mapError(error)
            }
        }
    }

    /// Maps to Finder's "Locked" flag (`uchg`, `.isUserImmutableKey`) — the
    /// checkbox Explorer's "Read-only" attribute corresponds to on macOS —
    /// rather than clearing the owner's POSIX write bit, which the owner
    /// could just `chmod` back and which Finder doesn't expose as a toggle.
    func setReadOnly(_ readOnly: Bool, for items: [FileSystemItem]) throws {
        for item in items {
            var url = item.url
            var values = URLResourceValues()
            values.isUserImmutable = readOnly
            do {
                try url.setResourceValues(values)
            } catch {
                throw Self.mapError(error)
            }
        }
    }

    /// Appends a numeric suffix to avoid overwriting an existing item with
    /// the same name in the destination directory (e.g. when copying into a
    /// folder that already contains a same-named file).
    private func uniqueDestination(for sourceURL: URL, in directory: URL) -> URL {
        let originalName = sourceURL.lastPathComponent
        var candidate = directory.appendingPathComponent(originalName)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let ext = sourceURL.pathExtension
        let base = sourceURL.deletingPathExtension().lastPathComponent
        var suffix = 2
        repeat {
            let name = ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
            candidate = directory.appendingPathComponent(name)
            suffix += 1
        } while fileManager.fileExists(atPath: candidate.path)

        return candidate
    }

    // `nonisolated`: static members of an actor type default to the
    // project's global main-actor isolation, not the actor's own isolation —
    // without this, every call site inside this actor's instance methods is
    // a cross-actor hop into MainActor just to format an error.
    private nonisolated static func mapError(_ error: Error) -> FileOperationError {
        let nsError = error as NSError
        switch nsError.code {
        case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
            return .permissionDenied
        case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
            return .notFound
        default:
            return .underlying(error)
        }
    }
}
