import SwiftUI

/// The root Explorer window: a tab bar, sidebar + file list, with a
/// Back/Forward/Up toolbar and an address bar on its own row beneath it,
/// mirroring Windows 11 Explorer's layout.
struct ExplorerView: View {
    @State private var windowModel = ExplorerWindowModel(startingAt: FileManager.default.homeDirectoryForCurrentUser)
    @State private var favoritesStore = FavoritesStore()
    @State private var connectionsStore = ConnectionsStore()
    @State private var isShowingInspector = false

    /// AppKit provides a per-window `UndoManager` automatically via the
    /// responder chain; SwiftUI surfaces it here. Handed to each tab's view
    /// model so file operations can register undo/redo steps (Cmd-Z /
    /// Cmd-Shift-Z, and the Edit menu, come for free from `UndoManager`
    /// itself). All tabs in a window share the same `UndoManager`, matching
    /// how undo works in every other macOS tabbed-document app.
    @Environment(\.undoManager) private var undoManager

    /// The active tab's view model — a computed property (not `@Bindable`)
    /// since it changes identity whenever the selected tab changes. Child
    /// views (`SidebarView`, `FileListView`, etc.) each declare their own
    /// `@Bindable var viewModel:` parameter, so passing a freshly-read
    /// reference here each body evaluation is all they need.
    private var viewModel: ExplorerViewModel { windowModel.selectedViewModel }

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel, favoritesStore: favoritesStore, connectionsStore: connectionsStore) { urls, destination, asCopy in
                Task {
                    await viewModel.moveOrCopy(urls, into: destination, asCopy: asCopy)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            VStack(spacing: 0) {
                TabBarView(windowModel: windowModel)

                Divider()

                BreadcrumbBar(viewModel: viewModel)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                Divider()

                FileListView(viewModel: viewModel) {
                    Task { await viewModel.createFolder() }
                }

                Divider()

                StatusBarView(viewModel: viewModel)
            }
            // Forces a clean remount of per-tab transient view state (the
            // breadcrumb's edit-path mode, its chevron popover, etc.) when
            // switching tabs, rather than leaving that state attached to
            // whatever happened to be at the same position in the view tree.
            .id(windowModel.selectedTabID)
            .searchable(text: searchQueryBinding, placement: .toolbar, prompt: "Поиск")
            .inspector(isPresented: $isShowingInspector) {
                InspectorView(viewModel: viewModel)
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: viewModel.goBack) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!viewModel.canGoBack)

                    Button(action: viewModel.goForward) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!viewModel.canGoForward)

                    Button(action: viewModel.goUp) {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(!viewModel.canGoUp)
                }

                ToolbarItemGroup {
                    Button {
                        Task { await viewModel.createFolder() }
                    } label: {
                        Label("Новая папка", systemImage: "folder.badge.plus")
                    }

                    Toggle(isOn: showHiddenBinding) {
                        Label("Скрытые файлы", systemImage: "eye")
                    }

                    Toggle(isOn: $isShowingInspector) {
                        Label("Сведения", systemImage: "sidebar.trailing")
                    }

                    Menu {
                        ForEach(FileListColumn.allCases) { column in
                            Toggle(column.title, isOn: columnBinding(for: column))
                        }
                    } label: {
                        Label("Столбцы", systemImage: "tablecells")
                    }
                }
            }
        }
        .task(id: windowModel.selectedTabID) {
            await viewModel.reload()
        }
        .onAppear {
            for tab in windowModel.tabs {
                tab.undoManager = undoManager
            }
        }
        .onChange(of: windowModel.tabs.count) {
            // New tabs (e.g. from Cmd-T) need the same shared undo manager.
            for tab in windowModel.tabs where tab.undoManager == nil {
                tab.undoManager = undoManager
            }
        }
    }

    private var searchQueryBinding: Binding<String> {
        Binding(
            get: { viewModel.searchQuery },
            set: { viewModel.searchQuery = $0 }
        )
    }

    private var showHiddenBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showHidden },
            set: { viewModel.showHidden = $0 }
        )
    }

    private func columnBinding(for column: FileListColumn) -> Binding<Bool> {
        Binding(
            get: { viewModel.visibleColumns.contains(column) },
            set: { isOn in
                if isOn {
                    viewModel.visibleColumns.insert(column)
                } else {
                    viewModel.visibleColumns.remove(column)
                }
            }
        )
    }
}
