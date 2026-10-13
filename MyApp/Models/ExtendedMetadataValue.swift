import Foundation

/// One Spotlight-derived, display-ready field for the Properties "Подробно"
/// tab — built by `FileMetadataService.spotlightMetadata(for:)`. Only
/// fields that actually have a value for the item are produced.
nonisolated struct ExtendedMetadataValue: Identifiable, Sendable {
    let id: String
    let group: String
    let label: String
    let value: String

    init(group: String, label: String, value: String) {
        self.id = "\(group).\(label)"
        self.group = group
        self.label = label
        self.value = value
    }
}
