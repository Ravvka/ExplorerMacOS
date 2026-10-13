import Foundation
import Observation

/// Persists non-secret `RemoteConnection` metadata (host/port/username/
/// protocol) via `UserDefaults` as JSON — parallels `FavoritesStore`.
/// Passwords never live here; see `KeychainCredentialStore`.
@Observable
@MainActor
final class ConnectionsStore {
    private static let defaultsKey = "ExplorerMacOS.remoteConnections"
    private let userDefaults: UserDefaults

    private(set) var connections: [RemoteConnection] = []

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        load()
    }

    func add(_ connection: RemoteConnection) {
        connections.append(connection)
        persist()
    }

    func update(_ connection: RemoteConnection) {
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        connections[index] = connection
        persist()
    }

    func remove(_ connection: RemoteConnection) {
        connections.removeAll { $0.id == connection.id }
        persist()
        try? KeychainCredentialStore.deletePassword(for: connection.id)
    }

    private func load() {
        guard let data = userDefaults.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([RemoteConnection].self, from: data)
        else { return }
        connections = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        userDefaults.set(data, forKey: Self.defaultsKey)
    }
}
