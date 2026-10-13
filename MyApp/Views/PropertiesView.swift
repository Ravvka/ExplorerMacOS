import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// "Свойства" — Explorer's Properties dialog. For a single item: Общие /
/// Разрешения / Подробно tabs. For several items: a simplified combined
/// summary (`MultiItemPropertiesView`), matching how Explorer's own
/// Properties dialog collapses to a General-only view for a multi-selection.
///
/// A Windows-style ACL "Security" editor, a "Sharing" tab, and a
/// "Previous Versions" tab are intentionally left out — macOS's POSIX+ACL
/// model doesn't map onto Windows' DACL editor, this app has no network
/// file-sharing feature of its own, and Previous Versions would need a
/// separate Time Machine integration. "Разрешения" below is a read-only
/// POSIX summary (owner/group/mode), not an ACL editor.
struct PropertiesView: View {
    let target: PropertiesTarget
    @Bindable var viewModel: ExplorerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch target {
                case .single(let item):
                    SingleItemPropertiesView(item: item, viewModel: viewModel)
                case .multiple(let items):
                    MultiItemPropertiesView(items: items, viewModel: viewModel)
                }
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Готово") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 440, height: 560)
    }
}

/// The full tabbed dialog for exactly one item.
private struct SingleItemPropertiesView: View {
    let item: FileSystemItem
    @Bindable var viewModel: ExplorerViewModel

    @State private var attributes: ItemAttributes?
    @State private var folderStats: FolderStatistics?
    @State private var extendedMetadata: [ExtendedMetadataValue] = []

    var body: some View {
        TabView {
            generalTab
                .tabItem { Text("Общие") }
            permissionsTab
                .tabItem { Text("Разрешения") }
            detailsTab
                .tabItem { Text("Подробно") }
        }
        .task(id: item.id) {
            attributes = await viewModel.attributes(for: item)
            extendedMetadata = await viewModel.spotlightMetadata(for: item)
        }
        .task(id: item.id) {
            guard item.isDirectory else { return }
            folderStats = nil
            do {
                for try await stats in viewModel.folderStatisticsStream(for: [item]) {
                    folderStats = stats
                }
            } catch {
                // A cancelled walk (sheet closed) throws `CancellationError`;
                // nothing to show for that, the partial result just stays.
            }
        }
    }

    // MARK: Общие

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider()

            if !item.isDirectory, let size = item.fileSize {
                PropertyRow(label: "Размер", value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }
            if let allocated = attributes?.totalAllocatedSize {
                PropertyRow(label: "На диске", value: ByteCountFormatter.string(fromByteCount: allocated, countStyle: .file))
            }
            if item.isDirectory {
                folderSizeRow
            }

            PropertyRow(label: "Расположение", value: locationString)

            if item.url.isFileURL, !item.isDirectory {
                openWithRow
            }

            if let created = item.contentCreationDate {
                PropertyRow(label: "Создан", value: created.formatted(date: .abbreviated, time: .shortened))
            }
            if let modified = item.contentModificationDate {
                PropertyRow(label: "Изменён", value: modified.formatted(date: .abbreviated, time: .shortened))
            }
            if let accessed = attributes?.accessDate {
                PropertyRow(label: "Открыт", value: accessed.formatted(date: .abbreviated, time: .shortened))
            }

            Divider()

            attributesSection

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            Menu {
                iconMenuContent
            } label: {
                Image(nsImage: item.icon)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .id(viewModel.iconRevision)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!(viewModel.providerCapabilities.supportsAttributeEditing && item.url.isFileURL))

            VStack(alignment: .leading) {
                Text(item.name).font(.headline)
                Text(item.typeDescription).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var iconMenuContent: some View {
        Button("Выбрать изображение…") { presentIconImporter() }
        Button("Вставить из буфера обмена") { pasteIconFromPasteboard() }
            .disabled(!NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil))
        Button("Восстановить стандартный значок") { viewModel.setCustomIcon(nil, for: item) }
    }

    private func presentIconImporter() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        viewModel.setCustomIcon(image, for: item)
    }

    private func pasteIconFromPasteboard() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage else { return }
        viewModel.setCustomIcon(image, for: item)
    }

    @ViewBuilder
    private var folderSizeRow: some View {
        if let folderStats {
            PropertyRow(
                label: folderStats.isComplete ? "Размер" : "Размер (вычисление…)",
                value: ByteCountFormatter.string(fromByteCount: folderStats.logicalSize, countStyle: .file)
            )
            PropertyRow(
                label: "Содержит",
                value: "\(folderStats.fileCount) файлов, \(folderStats.folderCount) папок"
            )
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Вычисление размера…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var openWithRow: some View {
        let defaultAppURL = OpenWithPicker.defaultApplication(for: item.url)
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Приложение")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(defaultAppURL.map(OpenWithPicker.displayName(for:)) ?? "Не определено")
                    .font(.callout)
            }
            Spacer()
            Menu("Изменить…") {
                OpenWithMenuContent(item: item) { appURL in
                    OpenWithPicker.setDefaultApplication(appURL, forFile: item.url) { error in
                        if let error {
                            Task { @MainActor in viewModel.activeError = .underlying(error) }
                        }
                    }
                }
                if let contentType = item.contentType {
                    Divider()
                    Button("Для всех файлов этого типа…") {
                        OpenWithPicker.setDefaultApplication(
                            OpenWithPicker.defaultApplication(for: item.url) ?? item.url,
                            forType: contentType
                        )
                    }
                }
            }
            .menuStyle(.button)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var attributesSection: some View {
        Toggle(isOn: Binding(
            get: { attributes?.isLocked ?? false },
            set: { newValue in Task { await viewModel.setReadOnly(newValue, for: [item]) } }
        )) {
            Text("Только для чтения")
        }
        .disabled(!viewModel.providerCapabilities.supportsAttributeEditing)

        Toggle(isOn: Binding(
            get: { item.isHidden },
            set: { newValue in Task { await viewModel.setHidden(newValue, for: [item]) } }
        )) {
            Text("Скрытый")
        }
        .disabled(!viewModel.providerCapabilities.supportsAttributeEditing || item.name.hasPrefix("."))

        if let attributes {
            PropertyRow(
                label: "Вы можете",
                value: [attributes.isReadable ? "читать" : nil, attributes.isWritable ? "записывать" : nil]
                    .compactMap { $0 }.joined(separator: " и ").ifEmpty("нет доступа")
            )
        }
    }

    private var locationString: String {
        let parent = item.url.deletingLastPathComponent()
        return parent.isFileURL ? parent.path : parent.absoluteString
    }

    // MARK: Разрешения

    private var permissionsTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let attributes {
                PropertyRow(label: "Владелец", value: "\(attributes.ownerName ?? "—") — \(attributes.roleDescription(for: .owner))")
                PropertyRow(label: "Группа", value: "\(attributes.groupName ?? "—") — \(attributes.roleDescription(for: .group))")
                PropertyRow(label: "Остальные", value: attributes.roleDescription(for: .others))
                Divider()
                PropertyRow(label: "Режим", value: "\(attributes.modeString)  (\(attributes.octalString))")
            } else {
                ProgressView()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: Подробно

    private var detailsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                PropertyRow(label: "Полный путь", value: item.url.isFileURL ? item.url.path : item.url.absoluteString)
                if let contentType = item.contentType {
                    PropertyRow(label: "Идентификатор типа (UTI)", value: contentType.identifier)
                    if let mime = contentType.preferredMIMEType {
                        PropertyRow(label: "MIME", value: mime)
                    }
                }
                if !item.isDirectory {
                    PropertyRow(label: "Расширение", value: item.url.pathExtension.isEmpty ? "—" : item.url.pathExtension)
                }

                if extendedMetadata.isEmpty {
                    Text("Spotlight не проиндексировал этот файл.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                } else {
                    ForEach(groupedMetadata, id: \.0) { group, values in
                        Divider()
                        Text(group)
                            .font(.subheadline.bold())
                        ForEach(values) { value in
                            PropertyRow(label: value.label, value: value.value)
                        }
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
    }

    private var groupedMetadata: [(String, [ExtendedMetadataValue])] {
        let groups = Dictionary(grouping: extendedMetadata, by: \.group)
        let order = ["Документ", "Изображение", "Камера", "Аудио и видео", "Происхождение"]
        return order.compactMap { group in groups[group].map { (group, $0) } }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
