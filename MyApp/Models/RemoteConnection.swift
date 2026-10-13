import Foundation

/// Which remote protocol a saved connection uses.
///
/// `nonisolated`: a plain value type shouldn't inherit the project's default
/// main-actor isolation — without this, reading `.defaultPort` from
/// `SMBMountService` (an `actor`, not `@MainActor`) is a cross-actor hop.
nonisolated enum ConnectionProtocolKind: String, Codable, CaseIterable, Identifiable {
    case smb
    case sftp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smb: return "SMB (Windows)"
        case .sftp: return "SFTP (Linux/SSH)"
        }
    }

    var defaultPort: Int {
        switch self {
        case .smb: return 445
        case .sftp: return 22
        }
    }
}

/// Non-secret metadata for a saved remote server connection — the password
/// (or SSH key passphrase) never lives here, only in
/// `KeychainCredentialStore`. Persisted via `ConnectionsStore`.
struct RemoteConnection: Identifiable, Hashable, Codable {
    let id: UUID
    var displayName: String
    var protocolKind: ConnectionProtocolKind
    var host: String
    var port: Int
    var username: String

    /// The share/export name for SMB (e.g. "Shared"); unused for SFTP, which
    /// browses from the account's home directory or `/`.
    var shareName: String?

    init(
        id: UUID = UUID(),
        displayName: String,
        protocolKind: ConnectionProtocolKind,
        host: String,
        port: Int? = nil,
        username: String,
        shareName: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.protocolKind = protocolKind
        self.host = host
        self.port = port ?? protocolKind.defaultPort
        self.username = username
        self.shareName = shareName
    }
}
