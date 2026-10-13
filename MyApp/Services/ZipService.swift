import Foundation

/// Compresses files/folders into a ZIP archive by shelling out to
/// `/usr/bin/zip`, which — unlike `ditto`'s single-source model — natively
/// accepts multiple source items for one archive, matching Finder's
/// "Compress N items" behavior for a multi-selection.
///
/// Local-provider-only: there's no remote equivalent of this (gated via
/// `FileSystemCapabilities.supportsZipCompress` at the call site).
enum ZipService {
    enum ZipError: LocalizedError {
        case noItems
        case processFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .noItems:
                return "Нечего сжимать."
            case .processFailed(let code):
                return "Не удалось создать ZIP-архив (код \(code))."
            }
        }
    }

    /// Creates `destinationZIPURL` containing `urls` at the archive root.
    /// All `urls` must share the same parent directory.
    static func compress(_ urls: [URL], into destinationZIPURL: URL) async throws {
        guard let parentDirectory = urls.first?.deletingLastPathComponent() else {
            throw ZipError.noItems
        }
        let itemNames = urls.map(\.lastPathComponent)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.currentDirectoryURL = parentDirectory
            process.arguments = ["-r", "-y", destinationZIPURL.path] + itemNames

            process.terminationHandler = { finishedProcess in
                if finishedProcess.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ZipError.processFailed(finishedProcess.terminationStatus))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
