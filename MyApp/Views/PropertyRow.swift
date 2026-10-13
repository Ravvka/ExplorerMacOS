import AppKit
import SwiftUI

/// Label + selectable value — shared by the Properties dialog and the
/// inspector's Details pane, which both showed the same row shape
/// independently before this was pulled out.
struct PropertyRow: View {
    let label: String
    let value: String

    var body: some View {
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

/// Icon + name + type header — the read-only shape shared by the inspector's
/// Details pane. The Properties dialog builds its own header instead, since
/// its icon needs to be interactive (the "Изменить значок" menu).
struct ItemHeaderView: View {
    let icon: NSImage
    let name: String
    let typeDescription: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                    .lineLimit(2)
                Text(typeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
