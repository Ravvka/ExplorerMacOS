import CoreServices
import Foundation

/// Read-only enrichment queries for the Properties dialog — Spotlight
/// metadata, owner/group/POSIX info, and recursive folder-size walks.
///
/// Deliberately **not** part of `FileSystemProviding`: these are local-disk/
/// Spotlight-specific enrichments a remote SFTP provider either can't
/// produce (Spotlight indexing, allocated size) or would need a completely
/// different, much slower approach for (a recursive walk over SFTP is
/// thousands of round trips). The protocol stays pure CRUD; this is a
/// separate, local-only helper gated by `url.isFileURL` at the call site.
actor FileMetadataService {
    // MARK: - Basic attributes (owner/group/POSIX mode, locked/hidden, allocated size)

    private static let resourceKeys: Set<URLResourceKey> = [
        .totalFileAllocatedSizeKey,
        .contentAccessDateKey,
        .attributeModificationDateKey,
        .isUserImmutableKey,
        .isReadableKey,
        .isWritableKey,
        .isPackageKey,
    ]

    func attributes(for url: URL, isDirectory: Bool) -> ItemAttributes {
        let resourceValues = try? url.resourceValues(forKeys: Self.resourceKeys)
        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)

        return ItemAttributes(
            isDirectory: isDirectory,
            totalAllocatedSize: resourceValues?.totalFileAllocatedSize.map(Int64.init),
            accessDate: resourceValues?.contentAccessDate,
            attributeModificationDate: resourceValues?.attributeModificationDate,
            isLocked: resourceValues?.isUserImmutable ?? false,
            isReadable: resourceValues?.isReadable ?? true,
            isWritable: resourceValues?.isWritable ?? true,
            isPackage: resourceValues?.isPackage ?? false,
            ownerName: fileAttributes?[.ownerAccountName] as? String,
            groupName: fileAttributes?[.groupOwnerAccountName] as? String,
            posixMode: (fileAttributes?[.posixPermissions] as? NSNumber)?.uint16Value
        )
    }

    // MARK: - Spotlight metadata (macOS's equivalent of Explorer's per-format Details tab)

    func spotlightMetadata(for url: URL) -> [ExtendedMetadataValue] {
        guard let metadataItem = NSMetadataItem(url: url) else { return [] }
        var results: [ExtendedMetadataValue] = []

        func add(_ group: String, _ label: String, _ attribute: CFString, _ transform: (Any) -> String? = { "\($0)" }) {
            guard let value = metadataItem.value(forAttribute: attribute as String) else { return }
            guard let text = transform(value), !text.isEmpty else { return }
            results.append(ExtendedMetadataValue(group: group, label: label, value: text))
        }

        add("Документ", "Заголовок", kMDItemTitle)
        add("Документ", "Авторы", kMDItemAuthors) { ($0 as? [String])?.joined(separator: ", ") }
        add("Документ", "Создано в", kMDItemCreator)
        add("Документ", "Версия", kMDItemVersion)
        add("Документ", "Страниц", kMDItemNumberOfPages) { ($0 as? NSNumber)?.stringValue }
        add("Документ", "Ключевые слова", kMDItemKeywords) { ($0 as? [String])?.joined(separator: ", ") }

        if let width = metadataItem.value(forAttribute: kMDItemPixelWidth as String) as? NSNumber,
           let height = metadataItem.value(forAttribute: kMDItemPixelHeight as String) as? NSNumber {
            results.append(ExtendedMetadataValue(group: "Изображение", label: "Размер", value: "\(width) × \(height)"))
        }
        add("Изображение", "Цветовое пространство", kMDItemColorSpace)
        add("Изображение", "Бит на канал", kMDItemBitsPerSample) { ($0 as? NSNumber)?.stringValue }

        add("Камера", "Производитель", kMDItemAcquisitionMake)
        add("Камера", "Модель", kMDItemAcquisitionModel)
        add("Камера", "Диафрагма", kMDItemFNumber) { ($0 as? NSNumber).map { "f/\($0)" } }
        add("Камера", "Выдержка", kMDItemExposureTimeSeconds) { ($0 as? NSNumber).map { "\($0) с" } }
        add("Камера", "ISO", kMDItemISOSpeed) { value in
            if let numbers = value as? [NSNumber] { return numbers.first?.stringValue }
            return (value as? NSNumber)?.stringValue
        }
        add("Камера", "Фокусное расстояние", kMDItemFocalLength) { ($0 as? NSNumber).map { "\($0) мм" } }

        add("Аудио и видео", "Длительность", kMDItemDurationSeconds) { value in
            (value as? NSNumber).map { self.formattedDuration($0.doubleValue) }
        }
        add("Аудио и видео", "Кодеки", kMDItemCodecs) { ($0 as? [String])?.joined(separator: ", ") }
        add("Аудио и видео", "Каналы", kMDItemAudioChannelCount) { ($0 as? NSNumber)?.stringValue }
        add("Аудио и видео", "Частота дискретизации", kMDItemAudioSampleRate) { ($0 as? NSNumber).map { "\(Int($0.doubleValue)) Гц" } }
        add("Аудио и видео", "Альбом", kMDItemAlbum)
        add("Аудио и видео", "Композитор", kMDItemComposer)
        add("Аудио и видео", "Жанр", kMDItemMusicalGenre)

        add("Происхождение", "Источник загрузки", kMDItemWhereFroms) { ($0 as? [String])?.joined(separator: ", ") }
        add("Происхождение", "Последнее открытие", kMDItemLastUsedDate) { ($0 as? Date)?.formatted(date: .abbreviated, time: .shortened) }
        add("Происхождение", "Комментарий Finder", kMDItemFinderComment)

        return results
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "\(Int(seconds)) с"
    }

    // MARK: - Recursive folder statistics

    /// Walks `roots` recursively, streaming periodic progress and a final
    /// result with `isComplete = true`. Cancelling the task that's consuming
    /// the stream (e.g. the Properties sheet closing) stops the walk via
    /// `onTermination`.
    nonisolated func folderStatistics(for roots: [URL]) -> AsyncThrowingStream<FolderStatistics, Error> {
        AsyncThrowingStream { continuation in
            // `Task.detached`, not a plain `Task { }`: a plain task would
            // inherit this actor's isolation, so one large walk would block
            // every other metadata call on this service for its duration.
            let task = Task.detached(priority: .userInitiated) {
                var stats = FolderStatistics()
                let keys: [URLResourceKey] = [.isDirectoryKey, .totalFileSizeKey, .totalFileAllocatedSizeKey]
                var lastEmit = ContinuousClock.now

                for root in roots {
                    guard let enumerator = FileManager.default.enumerator(
                        at: root,
                        includingPropertiesForKeys: keys,
                        options: [],
                        errorHandler: { _, _ in
                            stats.skippedCount += 1
                            return true
                        }
                    ) else { continue }

                    // `nextObject()`, not `for...in`: iterating an
                    // `NSEnumerator` via `Sequence`/`makeIterator()` is
                    // flagged as unsafe from an async context (a hard error
                    // under the Swift 6 language mode) — this is the
                    // documented safe alternative.
                    while let url = enumerator.nextObject() as? URL {
                        if Task.isCancelled { break }
                        guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                            stats.skippedCount += 1
                            continue
                        }
                        if values.isDirectory == true {
                            stats.folderCount += 1
                        } else {
                            stats.fileCount += 1
                            stats.logicalSize += Int64(values.totalFileSize ?? 0)
                            stats.allocatedSize += Int64(values.totalFileAllocatedSize ?? 0)
                        }

                        let now = ContinuousClock.now
                        if now - lastEmit > .milliseconds(200) {
                            lastEmit = now
                            continuation.yield(stats)
                        }
                    }
                    if Task.isCancelled { break }
                }

                if !Task.isCancelled {
                    stats.isComplete = true
                    continuation.yield(stats)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
