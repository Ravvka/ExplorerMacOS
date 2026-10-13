import SwiftUI

/// Simplified combined "Общие"-only view shown when several items are
/// selected for Properties — matching Explorer's own multi-selection
/// Properties dialog (count + total size + shared attributes only, no
/// per-item tabs).
struct MultiItemPropertiesView: View {
    let items: [FileSystemItem]
    @Bindable var viewModel: ExplorerViewModel

    @State private var folderStats: FolderStatistics?
    @State private var lockedByURL: [URL: Bool] = [:]

    private var fileCount: Int { items.filter { !$0.isDirectory }.count }
    private var folderCount: Int { items.filter(\.isDirectory).count }
    private var folderItems: [FileSystemItem] { items.filter(\.isDirectory) }

    /// Sum of plain file sizes plus whatever the folder walk has found so
    /// far (or already finished finding).
    private var totalSize: Int64 {
        let fileSize = items.filter { !$0.isDirectory }.reduce(Int64(0)) { $0 + ($1.fileSize ?? 0) }
        return fileSize + (folderStats?.logicalSize ?? 0)
    }

    private var commonTypeDescription: String? {
        let types = Set(items.map(\.typeDescription))
        return types.count == 1 ? types.first : nil
    }

    private var commonParent: URL? {
        let parents = Set(items.map { $0.url.deletingLastPathComponent() })
        return parents.count == 1 ? parents.first : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(items.count) объектов")
                .font(.headline)
            Text(summaryLine)
                .foregroundStyle(.secondary)

            Divider()

            PropertyRow(label: "Тип", value: commonTypeDescription ?? "Разные типы")
            PropertyRow(
                label: folderStats?.isComplete == false && !folderItems.isEmpty ? "Размер (вычисление…)" : "Размер",
                value: ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
            )
            if let commonParent {
                PropertyRow(label: "Расположение", value: commonParent.isFileURL ? commonParent.path : commonParent.absoluteString)
            } else {
                PropertyRow(label: "Расположение", value: "Разные папки")
            }

            Divider()

            Toggle(isOn: readOnlyBinding) {
                Text("Только для чтения")
            }
            .disabled(!viewModel.providerCapabilities.supportsAttributeEditing)

            Toggle(isOn: hiddenBinding) {
                Text("Скрытый")
            }
            .disabled(!viewModel.providerCapabilities.supportsAttributeEditing)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: folderItems.map(\.id)) {
            guard !folderItems.isEmpty else { return }
            folderStats = nil
            do {
                for try await stats in viewModel.folderStatisticsStream(for: folderItems) {
                    folderStats = stats
                }
            } catch {
                // Cancelled when the sheet closes — the partial result just stays.
            }
        }
        .task(id: items.map(\.id)) {
            var result: [URL: Bool] = [:]
            for item in items {
                result[item.url] = await viewModel.attributes(for: item).isLocked
            }
            lockedByURL = result
        }
    }

    private var summaryLine: String {
        switch (fileCount, folderCount) {
        case (0, let folders): return "\(folders) папок"
        case (let files, 0): return "\(files) файлов"
        default: return "\(fileCount) файлов, \(folderCount) папок"
        }
    }

    /// `Set`-backed mixed-state toggle: reading `isHidden` is unanimous
    /// (true only when every item agrees); setting applies to all items at
    /// once as a single undoable action, matching Explorer's checkbox
    /// behavior for a multi-selection.
    private var hiddenBinding: Binding<Bool> {
        Binding(
            get: { items.allSatisfy(\.isHidden) },
            set: { newValue in Task { await viewModel.setHidden(newValue, for: items) } }
        )
    }

    private var readOnlyBinding: Binding<Bool> {
        Binding(
            get: { !lockedByURL.isEmpty && items.allSatisfy { lockedByURL[$0.url] == true } },
            set: { newValue in Task { await viewModel.setReadOnly(newValue, for: items) } }
        )
    }
}
