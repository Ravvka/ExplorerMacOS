import AppKit
import SwiftUI

/// The Explorer-style sidebar: built-in "Избранное" locations plus
/// user-added "Разделы", with drag & drop support for moving files into a
/// folder by dropping them on its sidebar row.
struct SidebarView: View {
    @Bindable var viewModel: ExplorerViewModel
    @Bindable var favoritesStore: FavoritesStore
    @Bindable var connectionsStore: ConnectionsStore
    let onDropItems: (_ urls: [URL], _ destination: URL, _ asCopy: Bool) -> Void

    @State private var connectViewModel = ConnectViewModel()
    @State private var isShowingConnectSheet = false

    private let builtInFavorites: [SidebarItem] = {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        func dir(_ name: FileManager.SearchPathDirectory, fallback: String) -> URL {
            fileManager.urls(for: name, in: .userDomainMask).first ?? home.appendingPathComponent(fallback)
        }
        return [
            SidebarItem(url: home, name: "Домой", systemImage: "house"),
            SidebarItem(url: dir(.desktopDirectory, fallback: "Desktop"), name: "Рабочий стол", systemImage: "menubar.dock.rectangle"),
            SidebarItem(url: dir(.documentDirectory, fallback: "Documents"), name: "Документы", systemImage: "doc"),
            SidebarItem(url: dir(.downloadsDirectory, fallback: "Downloads"), name: "Загрузки", systemImage: "arrow.down.circle"),
            SidebarItem(url: dir(.picturesDirectory, fallback: "Pictures"), name: "Изображения", systemImage: "photo"),
            SidebarItem(url: dir(.moviesDirectory, fallback: "Movies"), name: "Видео", systemImage: "film"),
            SidebarItem(url: dir(.musicDirectory, fallback: "Music"), name: "Музыка", systemImage: "music.note"),
            SidebarItem(url: URL(fileURLWithPath: "/Applications"), name: "Программы", systemImage: "square.grid.2x2"),
        ]
    }()

    /// Cached, not recomputed on every body evaluation — enumerating mounted
    /// volumes is a real syscall, not a cheap in-memory read, so it's
    /// refreshed only on appear and when a volume actually mounts/unmounts
    /// (via `NotificationCenter`'s async-sequence API, not Combine, per this
    /// project's no-Combine convention).
    @State private var mountedVolumes: [SidebarItem] = []

    @State private var isShowingAddFolderPanel = false

    var body: some View {
        List(selection: Binding(
            get: { viewModel.currentDirectoryURL },
            set: { if let url = $0 { viewModel.navigate(to: url) } }
        )) {
            Section("Избранное") {
                ForEach(builtInFavorites) { item in
                    row(for: item)
                }
            }

            Section("Разделы") {
                ForEach(favoritesStore.items) { item in
                    row(for: item)
                        .contextMenu {
                            Button("Удалить из разделов", role: .destructive) {
                                favoritesStore.remove(url: item.url)
                            }
                        }
                }
                ForEach(mountedVolumes) { item in
                    row(for: item)
                }

                Button {
                    presentAddFolderPanel()
                } label: {
                    Label("Добавить папку…", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Section("Подключения") {
                ForEach(connectionsStore.connections) { connection in
                    Button {
                        Task { await connectToSaved(connection) }
                    } label: {
                        Label(connection.displayName, systemImage: connectionIcon(for: connection.protocolKind))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Удалить подключение", role: .destructive) {
                            connectionsStore.remove(connection)
                        }
                    }
                }

                Button {
                    connectViewModel.reset()
                    isShowingConnectSheet = true
                } label: {
                    Label("Подключиться к серверу…", systemImage: "network")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .sheet(isPresented: $isShowingConnectSheet) {
            ConnectToServerView(connectViewModel: connectViewModel) { connection, password in
                await performNewConnection(connection, password: password)
            }
        }
        .task {
            refreshMountedVolumes()
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: NSWorkspace.didMountNotification) {
                refreshMountedVolumes()
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: NSWorkspace.didUnmountNotification) {
                refreshMountedVolumes()
            }
        }
    }

    private func refreshMountedVolumes() {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey],
            options: [.skipHiddenVolumes]
        ) ?? []
        mountedVolumes = urls.map { url in
            let name = (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? url.lastPathComponent
            return SidebarItem(url: url, name: name, systemImage: "externaldrive")
        }
    }

    private func row(for item: SidebarItem) -> some View {
        Label(item.name, systemImage: item.systemImage)
            .tag(item.url)
            .dropDestination(for: URL.self) { urls, _ in
                // SwiftUI's drop API doesn't surface modifier keys itself —
                // reading `NSEvent.modifierFlags` at drop time is the
                // standard workaround. Option = copy, matching Finder;
                // plain drag = move, matching Explorer's default for a
                // same-provider drag.
                let asCopy = NSEvent.modifierFlags.contains(.option)
                onDropItems(urls, item.url, asCopy)
            }
    }

    private func connectionIcon(for kind: ConnectionProtocolKind) -> String {
        switch kind {
        case .smb: return "externaldrive.connected.to.line.below"
        case .sftp: return "terminal"
        }
    }

    private func connectToSaved(_ connection: RemoteConnection) async {
        let password = (try? KeychainCredentialStore.password(for: connection.id)) ?? nil
        _ = await viewModel.connect(to: connection, password: password ?? "")
    }

    /// Used by the "Connect to Server" sheet: attempts the connection first,
    /// and only persists it (connection metadata + Keychain password) once
    /// it actually succeeds — a failed attempt shouldn't clutter the saved
    /// "Подключения" list.
    private func performNewConnection(_ connection: RemoteConnection, password: String) async -> Bool {
        let succeeded = await viewModel.connect(to: connection, password: password)
        if succeeded {
            connectionsStore.add(connection)
            try? KeychainCredentialStore.savePassword(password, for: connection.id)
        } else {
            connectViewModel.errorMessage = viewModel.activeError?.localizedDescription
        }
        return succeeded
    }

    private func presentAddFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Добавить"

        if panel.runModal() == .OK, let url = panel.url {
            favoritesStore.add(url: url)
        }
    }
}
