import Foundation

/// Progress/result of a recursive folder-size walk, streamed from
/// `FileMetadataService.folderStatistics(for:)` — Explorer's "Calculating…"
/// General-tab line for folders.
nonisolated struct FolderStatistics: Sendable {
    var fileCount = 0
    var folderCount = 0
    var logicalSize: Int64 = 0
    var allocatedSize: Int64 = 0
    /// Entries that couldn't be read (permission errors, etc.) — the walk
    /// continues past these rather than failing outright, matching Finder.
    var skippedCount = 0
    var isComplete = false
}
