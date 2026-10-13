import AppKit
import SwiftUI

/// An Explorer-style address bar: clickable path segments by default, with a
/// click-to-edit mode that swaps in a text field for direct path entry.
struct BreadcrumbBar: View {
    /// Reads `currentDirectoryURL` straight from the view model, rather than
    /// taking a plain `URL` snapshot, so this view's own body re-evaluates on
    /// navigation even when embedded inside a `.toolbar` content closure
    /// (whose re-invocation on macOS is otherwise unreliable).
    @Bindable var viewModel: ExplorerViewModel

    @State private var isEditing = false
    @State private var editedPath = ""
    @FocusState private var isFieldFocused: Bool

    /// Which segment's chevron dropdown is currently open, and the
    /// subfolders loaded for it (`nil` while loading, distinct from an
    /// empty array meaning "no subfolders").
    @State private var chevronPopoverURL: URL?
    @State private var chevronSubfolders: [FileSystemItem]?

    private var currentDirectoryURL: URL { viewModel.currentDirectoryURL }

    var body: some View {
        Group {
            if isEditing {
                TextField("Путь", text: $editedPath)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFieldFocused)
                    .onSubmit(commitEditedPath)
                    .onExitCommand { isEditing = false }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(pathSegments, id: \.url) { segment in
                            Button(segment.name) {
                                viewModel.navigate(to: segment.url)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(segment.url == currentDirectoryURL ? .primary : .secondary)

                            if segment.url != currentDirectoryURL {
                                // Tapping the chevron (not the segment name
                                // itself) pops up that segment's subfolders,
                                // for a quick lateral jump — matching
                                // Explorer's address-bar chevron menus.
                                Button {
                                    loadSubfolders(of: segment.url)
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: Binding(
                                    get: { chevronPopoverURL == segment.url },
                                    set: { isPresented in
                                        if !isPresented { chevronPopoverURL = nil }
                                    }
                                )) {
                                    subfoldersMenu
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    editedPath = currentDirectoryURL.path
                    isEditing = true
                    isFieldFocused = true
                }
                .contextMenu {
                    Button("Скопировать путь") {
                        copyPathToPasteboard()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
    }

    /// Copies the current folder's full path as plain text, matching
    /// Explorer's "Copy address as text" on the address bar.
    private func copyPathToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(currentDirectoryURL.path, forType: .string)
    }

    private func loadSubfolders(of url: URL) {
        chevronSubfolders = nil
        chevronPopoverURL = url
        Task {
            let subfolders = await viewModel.subfolders(of: url)
            // Discard the result if the user already closed this popover or
            // opened a different one while the load was in flight.
            if chevronPopoverURL == url {
                chevronSubfolders = subfolders
            }
        }
    }

    @ViewBuilder
    private var subfoldersMenu: some View {
        if let subfolders = chevronSubfolders {
            if subfolders.isEmpty {
                Text("Нет вложенных папок")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List(subfolders) { item in
                    Button {
                        viewModel.navigate(to: item.url)
                        chevronPopoverURL = nil
                    } label: {
                        Label(item.name, systemImage: "folder")
                    }
                    .buttonStyle(.plain)
                }
                .frame(minWidth: 220, maxHeight: 300)
            }
        } else {
            ProgressView()
                .padding()
        }
    }

    private func commitEditedPath() {
        let trimmed = editedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if FileManager.default.fileExists(atPath: trimmed) {
            viewModel.navigate(to: URL(fileURLWithPath: trimmed))
        }
        isEditing = false
    }

    private struct Segment {
        let url: URL
        let name: String
    }

    private var pathSegments: [Segment] {
        var segments: [Segment] = []
        var url = currentDirectoryURL
        segments.append(Segment(url: url, name: url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent))

        while url.pathComponents.count > 1 {
            url = url.deletingLastPathComponent()
            let name = url.pathComponents.count == 1 ? "Macintosh HD" : url.lastPathComponent
            segments.append(Segment(url: url, name: name))
        }
        return segments.reversed()
    }
}
