import Foundation

/// What the "Свойства" sheet is showing — a single item (the full tabbed
/// dialog) or several (a simplified combined summary), matching how
/// Explorer's Properties dialog collapses to one General-only view for a
/// multi-selection.
nonisolated enum PropertiesTarget: Identifiable {
    case single(FileSystemItem)
    case multiple([FileSystemItem])

    var id: String {
        switch self {
        case .single(let item):
            return item.url.absoluteString
        case .multiple(let items):
            return items.map(\.url.absoluteString).sorted().joined(separator: "|")
        }
    }

    var items: [FileSystemItem] {
        switch self {
        case .single(let item): return [item]
        case .multiple(let items): return items
        }
    }

    static func from(_ items: [FileSystemItem]) -> PropertiesTarget? {
        if items.isEmpty { return nil }
        if items.count == 1 { return .single(items[0]) }
        return .multiple(items)
    }
}
