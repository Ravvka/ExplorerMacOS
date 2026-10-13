import Foundation
import NetFS

/// Mounts an SMB share via the system's `NetFS` framework. Once mounted, the
/// share is a normal local path under `/Volumes/...`, so the existing
/// `LocalFileSystemService` handles everything else — no separate SMB
/// provider implementation is needed, per the project roadmap.
///
/// Caveat carried over from the roadmap: there's a documented Apple Silicon
/// issue where `NetFSMountURLSync`/`Async` can fail for a process that isn't
/// running as root or via a launchd/privileged-helper context, even though
/// the same call works on Intel. If `mount(connection:password:)` fails with
/// an unexpected status here, that's the most likely cause — confirming
/// it's not hit on the actual target hardware was flagged as a pre-requisite
/// spike that hasn't been run (this environment has no real SMB server to
/// mount against, so this implementation is written to the documented API
/// shape but not live-tested).
actor SMBMountService {
    enum SMBMountError: LocalizedError {
        case invalidConnection
        case mountFailed(Int32)
        case noMountPointReturned

        var errorDescription: String? {
            switch self {
            case .invalidConnection:
                return "Некорректные параметры SMB-подключения."
            case .mountFailed(let status):
                return "Не удалось подключиться к серверу (код \(status))."
            case .noMountPointReturned:
                return "Сервер подключился, но система не вернула точку монтирования."
            }
        }
    }

    /// Mounts the share described by `connection` and returns the local
    /// `file://` URL it ended up at (typically under `/Volumes`).
    func mount(connection: RemoteConnection, password: String) throws -> URL {
        guard connection.protocolKind == .smb else {
            throw SMBMountError.invalidConnection
        }

        var urlString = "smb://\(connection.host)"
        if connection.port != connection.protocolKind.defaultPort {
            urlString += ":\(connection.port)"
        }
        if let shareName = connection.shareName, !shareName.isEmpty {
            urlString += "/\(shareName)"
        }

        guard let smbURL = URL(string: urlString) else {
            throw SMBMountError.invalidConnection
        }

        var mountPoints: Unmanaged<CFArray>?
        let status = NetFSMountURLSync(
            smbURL as CFURL,
            nil, // mountdir: let the system choose under /Volumes
            connection.username as CFString,
            password as CFString,
            nil, // open_options: defaults
            nil, // mount_options: defaults
            &mountPoints
        )

        guard status == 0 else {
            throw SMBMountError.mountFailed(status)
        }

        guard let paths = mountPoints?.takeRetainedValue() as? [String], let firstPath = paths.first else {
            throw SMBMountError.noMountPointReturned
        }

        return URL(fileURLWithPath: firstPath, isDirectory: true)
    }
}
