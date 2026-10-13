import Foundation
import Observation

/// Owns the set of tabs in one Explorer window — the last piece of the
/// project roadmap, deliberately last because it's the one change that needs
/// a level of state above a single `ExplorerViewModel` (one per window until
/// now). Everything else (sidebar, toolbar, undo manager) still operates on
/// whichever tab is currently selected.
@Observable
@MainActor
final class ExplorerWindowModel {
    private(set) var tabs: [ExplorerViewModel]
    var selectedTabID: ExplorerViewModel.ID

    init(startingAt url: URL) {
        let firstTab = ExplorerViewModel(startingAt: url)
        self.tabs = [firstTab]
        self.selectedTabID = firstTab.id
    }

    var selectedViewModel: ExplorerViewModel {
        tabs.first { $0.id == selectedTabID } ?? tabs[0]
    }

    func addTab(startingAt url: URL) {
        let newTab = ExplorerViewModel(startingAt: url)
        tabs.append(newTab)
        selectedTabID = newTab.id
        Task { await newTab.reload() }
    }

    /// Keeps at least one tab open — closing the last tab in a window would
    /// otherwise leave it showing nothing, and SwiftUI doesn't give a child
    /// view an easy way to close its own window from here.
    func closeTab(_ id: ExplorerViewModel.ID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if selectedTabID == id {
            let newIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[newIndex].id
        }
    }

    func selectNextTab() {
        guard let currentIndex = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        let nextIndex = (currentIndex + 1) % tabs.count
        selectedTabID = tabs[nextIndex].id
    }

    func selectPreviousTab() {
        guard let currentIndex = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        let previousIndex = (currentIndex - 1 + tabs.count) % tabs.count
        selectedTabID = tabs[previousIndex].id
    }
}
