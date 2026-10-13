import SwiftUI

/// Metadata panel for the current selection, matching Explorer's Details
/// pane: icon/name/kind/size/dates/path for a single selected item, or a
/// combined count + size when multiple items are selected.
struct DetailsPaneView: View {
    @Bindable var viewModel: ExplorerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let item = singleSelectedItem {
                    singleItemDetails(item)
                } else if let summary = viewModel.selectionSummary {
                    Text("Выбрано: \(summary.count)")
                        .font(.headline)
                    Text(ByteCountFormatter.string(fromByteCount: summary.totalSize, countStyle: .file))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Ничего не выбрано")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var singleSelectedItem: FileSystemItem? {
        guard viewModel.selection.count == 1, let id = viewModel.selection.first else { return nil }
        return viewModel.items.first { $0.id == id }
    }

    @ViewBuilder
    private func singleItemDetails(_ item: FileSystemItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(item.typeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Divider()

        if !item.isDirectory, let size = item.fileSize {
            detailRow("Размер", ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if let modified = item.contentModificationDate {
            detailRow("Изменён", modified.formatted(date: .abbreviated, time: .shortened))
        }
        if let created = item.contentCreationDate {
            detailRow("Создан", created.formatted(date: .abbreviated, time: .shortened))
        }
        detailRow("Путь", item.url.isFileURL ? item.url.path : item.url.absoluteString)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
    }
}
