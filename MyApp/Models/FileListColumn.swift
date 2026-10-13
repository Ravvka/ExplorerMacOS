import Foundation

/// The optional columns `FileListView` can show in its Details table,
/// beyond the always-present Name column — matching Explorer's "Choose
/// columns" catalog. Column order in the table is fixed (declaration
/// order below); only visibility is user-configurable for now, not
/// reordering.
enum FileListColumn: String, CaseIterable, Identifiable {
    case dateModified
    case type
    case size
    case dateCreated
    case path

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateModified: return "Дата изменения"
        case .type: return "Тип"
        case .size: return "Размер"
        case .dateCreated: return "Дата создания"
        case .path: return "Путь"
        }
    }

    /// Shown by default — matches the table's original fixed four columns.
    static let defaultVisible: Set<FileListColumn> = [.dateModified, .type, .size]
}
