import AppKit
import SwiftUI

/// The Explorer-style "Details" list: a multi-column table (Name, Date
/// Modified, Type, Size) with sorting, inline rename, a right-click context
/// menu, and drag & drop between folders.
struct FileListView: View {
    @Bindable var viewModel: ExplorerViewModel
    let onCreateFolderRequested: () -> Void

    @State private var sortDescriptors: [KeyPathComparator<FileSystemItem>] = [
        KeyPathComparator(\FileSystemItem.name)
    ]

    var body: some View {
        Table(viewModel.items, selection: $viewModel.selection, sortOrder: $sortDescriptors) {
            TableColumn("Имя", sortUsing: KeyPathComparator(\FileSystemItem.name)) { item in
                NameCell(item: item, viewModel: viewModel)
            }
            .width(min: 180, ideal: 280)

            if viewModel.visibleColumns.contains(.dateModified) {
                TableColumn("Дата изменения", sortUsing: KeyPathComparator(\FileSystemItem.sortableModificationDate)) { item in
                    Text(item.contentModificationDate?.formatted(date: .numeric, time: .shortened) ?? "")
                        .foregroundStyle(.secondary)
                }
                .width(min: 120, ideal: 160)
            }

            if viewModel.visibleColumns.contains(.type) {
                TableColumn("Тип", sortUsing: KeyPathComparator(\FileSystemItem.typeDescription)) { item in
                    Text(item.typeDescription)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 120)
            }

            if viewModel.visibleColumns.contains(.size) {
                TableColumn("Размер", sortUsing: KeyPathComparator(\FileSystemItem.sortableSize)) { item in
                    Text(sizeString(for: item))
                        .foregroundStyle(.secondary)
                }
                .width(min: 60, ideal: 90)
            }

            if viewModel.visibleColumns.contains(.dateCreated) {
                TableColumn("Дата создания", sortUsing: KeyPathComparator(\FileSystemItem.sortableCreationDate)) { item in
                    Text(item.contentCreationDate?.formatted(date: .numeric, time: .shortened) ?? "")
                        .foregroundStyle(.secondary)
                }
                .width(min: 120, ideal: 160)
            }

            if viewModel.visibleColumns.contains(.path) {
                TableColumn("Путь", sortUsing: KeyPathComparator(\FileSystemItem.sortablePath)) { item in
                    Text(item.sortablePath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 150, ideal: 240)
            }
        }
        .onChange(of: sortDescriptors) { _, newValue in
            applySortDescriptor(newValue)
        }
        // Plain ⌫/⌦ moves the selection to the Trash, matching Finder.
        .onDeleteCommand {
            Task { await viewModel.delete(viewModel.selectedItems) }
        }
        .background {
            // ⌘⌫ (the shortcut Finder's File ▸ Move to Trash menu item
            // shows) and ⌥⌘⌫ ("Delete Immediately", bypassing the Trash).
            // Hidden buttons rather than `.onCommand` so each gets its own
            // distinct shortcut and disabled state tied to the selection.
            Group {
                Button("") {
                    Task { await viewModel.delete(viewModel.selectedItems) }
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(viewModel.selection.isEmpty)

                Button("") {
                    viewModel.requestPermanentDelete(viewModel.selectedItems)
                }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
                .disabled(viewModel.selection.isEmpty)
            }
            .hidden()
        }
        .contextMenu(forSelectionType: FileSystemItem.ID.self) { ids in
            contextMenuContent(for: ids)
        } primaryAction: { ids in
            if let id = ids.first, let item = viewModel.items.first(where: { $0.id == id }) {
                open(item)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            // SwiftUI's drop API doesn't surface modifier keys itself —
            // reading `NSEvent.modifierFlags` at drop time is the standard
            // workaround. Option = copy, matching Finder; plain drag = move.
            if NSEvent.modifierFlags.contains(.option) {
                viewModel.markForCopy(urls)
            } else {
                viewModel.markForCut(urls)
            }
            Task {
                await viewModel.pasteIntoCurrentDirectory()
            }
        }
        .overlay {
            if viewModel.items.isEmpty && !viewModel.isLoading {
                ContentUnavailableView("Папка пуста", systemImage: "folder")
            }
        }
        .sheet(item: $viewModel.propertiesTarget) { target in
            PropertiesView(target: target, viewModel: viewModel)
        }
        .alert(
            "Ошибка",
            isPresented: Binding(
                get: { viewModel.activeError != nil },
                set: { if !$0 { viewModel.activeError = nil } }
            )
        ) {
            Button("ОК", role: .cancel) {}
        } message: {
            Text(viewModel.activeError?.localizedDescription ?? "")
        }
        .alert(
            "Удалить без возможности восстановления?",
            isPresented: Binding(
                get: { viewModel.pendingPermanentDelete != nil },
                set: { if !$0 { viewModel.pendingPermanentDelete = nil } }
            ),
            presenting: viewModel.pendingPermanentDelete
        ) { _ in
            Button("Удалить", role: .destructive) {
                Task { await viewModel.confirmPermanentDelete() }
            }
            Button("Отмена", role: .cancel) {
                viewModel.pendingPermanentDelete = nil
            }
        } message: { itemsToDelete in
            Text(permanentDeleteMessage(for: itemsToDelete))
        }
    }

    private func permanentDeleteMessage(for itemsToDelete: [FileSystemItem]) -> String {
        if itemsToDelete.count == 1, let name = itemsToDelete.first?.name {
            return "Элемент «\(name)» будет удалён немедленно. Это действие нельзя отменить."
        }
        return "\(itemsToDelete.count) объектов будут удалены немедленно. Это действие нельзя отменить."
    }

    @ViewBuilder
    private func contextMenuContent(for ids: Set<FileSystemItem.ID>) -> some View {
        let selectedItems = viewModel.items.filter { ids.contains($0.id) }

        if selectedItems.count == 1, let item = selectedItems.first {
            Button("Открыть") { open(item) }

            if item.url.isFileURL, !item.isDirectory {
                openWithMenu(for: item)
            }

            Divider()
        }

        Button("Вырезать") {
            viewModel.markForCut(selectedItems.map(\.url))
        }
        .disabled(selectedItems.isEmpty)

        Button("Копировать") {
            viewModel.markForCopy(selectedItems.map(\.url))
        }
        .disabled(selectedItems.isEmpty)

        Button("Вставить") {
            Task { await viewModel.pasteIntoCurrentDirectory() }
        }

        Divider()

        if selectedItems.count == 1, let item = selectedItems.first {
            Button("Переименовать") {
                viewModel.renamingItemID = item.id
            }
        }

        Button("Удалить", role: .destructive) {
            Task { await viewModel.delete(selectedItems) }
        }
        .disabled(selectedItems.isEmpty)

        Divider()

        Menu("Создать") {
            Button("Папку") {
                onCreateFolderRequested()
            }

            Divider()

            Button("Текстовый документ") {
                Task { await viewModel.createFile(named: "Текстовый документ.txt") }
            }

            Button("Документ Rich Text") {
                Task { await viewModel.createFile(named: "Документ Rich Text.rtf") }
            }
        }

        if viewModel.providerCapabilities.supportsZipCompress, !selectedItems.isEmpty {
            Button("Сжать в ZIP") {
                Task { await viewModel.compressToZip(selectedItems) }
            }
        }

        if selectedItems.count == 1, let item = selectedItems.first {
            if viewModel.providerCapabilities.supportsAlias {
                Button("Создать алиас") {
                    Task { await viewModel.createAlias(for: item) }
                }
            }

            if viewModel.providerCapabilities.supportsRevealInFinder {
                Button("Показать в Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
            }
        }

        if !selectedItems.isEmpty {
            Divider()

            Button("Свойства") {
                viewModel.propertiesTarget = .from(selectedItems)
            }
        }
    }

    /// "Open With" submenu — lists every app that can open this file, with
    /// the current default marked, matching Explorer's "Open with" menu.
    @ViewBuilder
    private func openWithMenu(for item: FileSystemItem) -> some View {
        if !OpenWithPicker.availableApplications(for: item.url).isEmpty {
            Menu("Открыть с помощью") {
                OpenWithMenuContent(item: item)
            }
        }
    }

    private func open(_ item: FileSystemItem) {
        if item.isDirectory {
            viewModel.navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    private func sizeString(for item: FileSystemItem) -> String {
        guard !item.isDirectory, let size = item.fileSize else { return "" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Maps the Table's column-header sort state back onto the view model's
    /// `sortField`/`sortOrder`, which is what actually reorders `items`
    /// (keeping folders grouped before files, which a raw `KeyPathComparator`
    /// wouldn't do on its own).
    private func applySortDescriptor(_ descriptors: [KeyPathComparator<FileSystemItem>]) {
        guard let first = descriptors.first else { return }

        switch first.keyPath {
        case \FileSystemItem.name:
            viewModel.sortField = .name
        case \FileSystemItem.sortableModificationDate:
            viewModel.sortField = .dateModified
        case \FileSystemItem.typeDescription:
            viewModel.sortField = .type
        case \FileSystemItem.sortableSize:
            viewModel.sortField = .size
        case \FileSystemItem.sortableCreationDate:
            viewModel.sortField = .dateCreated
        case \FileSystemItem.sortablePath:
            viewModel.sortField = .path
        default:
            break
        }

        viewModel.sortOrder = first.order == .forward ? .forward : .reverse
    }
}

/// Icon + name cell, swapping to an editable `TextField` when this row is
/// the one being renamed.
private struct NameCell: View {
    let item: FileSystemItem
    @Bindable var viewModel: ExplorerViewModel

    @State private var editedName = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 16, height: 16)
                // `FileSystemItem` compares equal by `url` alone, so a
                // custom-icon change (which doesn't change the URL) needs
                // this explicit signal to get the row to redraw.
                .id(viewModel.iconRevision)

            if viewModel.renamingItemID == item.id {
                TextField("Имя", text: $editedName)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit(commitRename)
                    .onAppear {
                        editedName = item.name
                        isFocused = true
                    }
                    .onExitCommand { viewModel.renamingItemID = nil }
            } else {
                Text(item.name)
                    .lineLimit(1)
            }
        }
    }

    private func commitRename() {
        guard editedName != item.name else {
            viewModel.renamingItemID = nil
            return
        }
        Task { await viewModel.rename(item, to: editedName) }
    }
}
