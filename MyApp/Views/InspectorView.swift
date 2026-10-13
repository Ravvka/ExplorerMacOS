import SwiftUI

/// Combines the Preview and Details panes into one inspector panel.
///
/// Real Explorer/Finder toggle these as two independent panes; here they're
/// stacked in one `.inspector()` panel instead (preview on top, metadata
/// below) — a deliberate simplification rather than wiring up two separate
/// toggle states for a single trailing panel.
struct InspectorView: View {
    @Bindable var viewModel: ExplorerViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let url = singleSelectedFileURL {
                PreviewPaneView(url: url)
                    .frame(minHeight: 180, idealHeight: 240)
                Divider()
            }

            DetailsPaneView(viewModel: viewModel)
        }
        .frame(minWidth: 240, idealWidth: 280)
    }

    /// Preview only makes sense for exactly one selected, real local file
    /// (no folder preview, no multi-selection preview).
    private var singleSelectedFileURL: URL? {
        guard viewModel.selection.count == 1, let id = viewModel.selection.first,
              let item = viewModel.items.first(where: { $0.id == id }),
              !item.isDirectory, item.url.isFileURL
        else { return nil }
        return item.url
    }
}
