import SwiftUI

/// A thin status bar beneath the file list — item count, or selection
/// count + combined size when something is selected, matching Explorer's
/// status bar.
struct StatusBarView: View {
    @Bindable var viewModel: ExplorerViewModel

    var body: some View {
        HStack {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var statusText: String {
        if let summary = viewModel.selectionSummary {
            let sizeString = ByteCountFormatter.string(fromByteCount: summary.totalSize, countStyle: .file)
            return "Выбрано: \(summary.count) (\(sizeString))"
        }
        let count = viewModel.items.count
        return "\(count) \(itemsWord(for: count))"
    }

    /// Crude Russian plural agreement for "объект" (1 объект, 2 объекта, 5 объектов).
    private func itemsWord(for count: Int) -> String {
        let remainder100 = count % 100
        let remainder10 = count % 10
        if (11...14).contains(remainder100) {
            return "объектов"
        }
        switch remainder10 {
        case 1:
            return "объект"
        case 2, 3, 4:
            return "объекта"
        default:
            return "объектов"
        }
    }
}
