import SwiftUI

/// A row of browser-style tabs, one per open location in this window,
/// matching Windows 11 Explorer's tabbed address bar.
struct TabBarView: View {
    @Bindable var windowModel: ExplorerWindowModel

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(windowModel.tabs) { tab in
                        TabButton(
                            tab: tab,
                            isSelected: tab.id == windowModel.selectedTabID,
                            canClose: windowModel.tabs.count > 1,
                            onSelect: { windowModel.selectedTabID = tab.id },
                            onClose: { windowModel.closeTab(tab.id) }
                        )
                    }
                }
            }

            Button {
                windowModel.addTab(startingAt: windowModel.selectedViewModel.currentDirectoryURL)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .help("Новая вкладка")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.bar)

        // Hidden buttons carry the standard tab keyboard shortcuts — Cmd-T
        // for a new tab, Cmd-W to close the current one, Cmd-} / Cmd-{ to
        // cycle — without needing visible UI for them.
        .background {
            Group {
                Button("Новая вкладка") {
                    windowModel.addTab(startingAt: windowModel.selectedViewModel.currentDirectoryURL)
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Закрыть вкладку") {
                    windowModel.closeTab(windowModel.selectedTabID)
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(windowModel.tabs.count <= 1)

                Button("Следующая вкладка") {
                    windowModel.selectNextTab()
                }
                .keyboardShortcut("]", modifiers: .command)

                Button("Предыдущая вкладка") {
                    windowModel.selectPreviousTab()
                }
                .keyboardShortcut("[", modifiers: .command)
            }
            .hidden()
        }
    }
}

private struct TabButton: View {
    @Bindable var tab: ExplorerViewModel
    let isSelected: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(tab.currentDirectoryURL.lastPathComponent.isEmpty ? "/" : tab.currentDirectoryURL.lastPathComponent)
                .lineLimit(1)
                .font(.callout)

            if canClose, isHovering || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }
}
