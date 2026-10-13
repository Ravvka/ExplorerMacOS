import Foundation
import Observation

/// Form state for the "Connect to Server" sheet.
@Observable
@MainActor
final class ConnectViewModel {
    var displayName = ""
    var protocolKind: ConnectionProtocolKind = .smb {
        didSet {
            if portText.isEmpty || portText == String(oldValue.defaultPort) {
                portText = String(protocolKind.defaultPort)
            }
        }
    }
    var host = ""
    var portText = String(ConnectionProtocolKind.smb.defaultPort)
    var username = ""
    var password = ""
    var shareName = ""

    var isConnecting = false
    var errorMessage: String?

    var isValid: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func makeConnection() -> RemoteConnection {
        RemoteConnection(
            displayName: displayName.trimmingCharacters(in: .whitespaces).isEmpty ? host : displayName,
            protocolKind: protocolKind,
            host: host,
            port: Int(portText) ?? protocolKind.defaultPort,
            username: username,
            shareName: protocolKind == .smb ? (shareName.isEmpty ? nil : shareName) : nil
        )
    }

    func reset() {
        displayName = ""
        protocolKind = .smb
        host = ""
        portText = String(ConnectionProtocolKind.smb.defaultPort)
        username = ""
        password = ""
        shareName = ""
        isConnecting = false
        errorMessage = nil
    }
}
