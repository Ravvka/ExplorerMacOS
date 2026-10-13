import Foundation

/// Surfaced when the user tries to connect via SFTP before the backend is
/// wired up.
///
/// SFTP has no automation-tool path in this project to add a Swift Package
/// dependency (`Citadel`, SwiftNIO-based SSH/SFTP client — see the project
/// roadmap) without hand-editing `project.pbxproj`, which is explicitly
/// avoided here. **To finish SFTP support:**
///
/// 1. In Xcode: File → Add Package Dependencies… → paste
///    `https://github.com/orlandos-nl/Citadel` → add the `Citadel` product
///    to the `ExplorerMacOS` target.
/// 2. Replace this file's contents with an `actor SFTPFileSystemService:
///    FileSystemProviding` that opens an `SSHClient`/`SFTPClient` from
///    Citadel using a `RemoteConnection` + password (or key) from
///    `KeychainCredentialStore`, and implements `contents(of:showHidden:)`,
///    `rename`, `copy`, `move`, `delete`, `createFolder`, `data(for:)`, and
///    `write(_:to:)` against it. `FileSystemItem.url` for remote entries
///    should use a `sftp://user@host:port/path` scheme (see
///    `FileSystemItem.icon`'s `url.isFileURL` check, already written to
///    accommodate this).
/// 3. Wire a `.sftp` case into `ExplorerViewModel.connect(to:password:)`
///    (currently only `.smb` is implemented) to construct and use it.
///
/// Everything else SFTP needs — the connection model, Keychain-backed
/// credential storage, the "Connect to Server" UI, and the `Connections`
/// sidebar section — is already in place and protocol-agnostic.
struct SFTPNotYetAvailableError: LocalizedError {
    var errorDescription: String? {
        "Поддержка SFTP ещё не подключена к сборке — нужно вручную добавить " +
            "пакет Citadel через File → Add Package Dependencies в Xcode."
    }
}
