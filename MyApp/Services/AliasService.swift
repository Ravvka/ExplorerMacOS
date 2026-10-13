import Foundation

/// Creates real Finder aliases (not symlinks) — an alias survives the
/// original file being moved or renamed, which a plain symlink doesn't.
/// This is the closest macOS equivalent to Windows' "Create Shortcut";
/// there's no attempt to emulate a `.lnk` file.
///
/// Local-provider-only (gated via `FileSystemCapabilities.supportsAlias`).
enum AliasService {
    static func createAlias(for item: FileSystemItem, in destinationDirectory: URL) throws -> URL {
        let bookmarkData = try item.url.bookmarkData(options: .suitableForBookmarkFile)

        var candidate = destinationDirectory.appendingPathComponent("\(item.name) alias")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = destinationDirectory.appendingPathComponent("\(item.name) alias \(suffix)")
            suffix += 1
        }

        try URL.writeBookmarkData(bookmarkData, to: candidate)
        return candidate
    }
}
