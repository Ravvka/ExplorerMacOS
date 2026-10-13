import Foundation

/// Read-only enrichment data for the Properties dialog — fetched on demand
/// by `FileMetadataService`, not stored on `FileSystemItem`, to keep
/// directory listings fast (owner/group/POSIX-mode lookups are an extra
/// syscall per item we don't want to pay for every row in a big folder).
nonisolated struct ItemAttributes: Sendable {
    enum PermissionScope {
        case owner, group, others
    }

    let isDirectory: Bool
    let totalAllocatedSize: Int64?
    let accessDate: Date?
    let attributeModificationDate: Date?
    let isLocked: Bool
    let isReadable: Bool
    let isWritable: Bool
    let isPackage: Bool
    let ownerName: String?
    let groupName: String?
    let posixMode: UInt16?

    /// `-rwxr-xr-x`-style string, matching `ls -l`.
    var modeString: String {
        guard let posixMode else { return "—" }
        var result = isDirectory ? "d" : "-"
        let bits: [(UInt16, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x"),
        ]
        for (bit, character) in bits {
            result.append((posixMode & bit) != 0 ? character : "-")
        }
        return result
    }

    var octalString: String {
        guard let posixMode else { return "—" }
        return String(format: "0%o", posixMode & 0o777)
    }

    func roleDescription(for scope: PermissionScope) -> String {
        guard let posixMode else { return "—" }
        let readBit: UInt16
        let writeBit: UInt16
        switch scope {
        case .owner: readBit = 0o400; writeBit = 0o200
        case .group: readBit = 0o040; writeBit = 0o020
        case .others: readBit = 0o004; writeBit = 0o002
        }
        switch ((posixMode & readBit) != 0, (posixMode & writeBit) != 0) {
        case (true, true): return "Чтение и запись"
        case (true, false): return "Только чтение"
        case (false, true): return "Только запись"
        case (false, false): return "Нет доступа"
        }
    }
}
