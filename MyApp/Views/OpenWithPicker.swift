import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Shared "Open With" logic (Launch Services calls, not `FileSystemProviding`
/// methods — these are app-association metadata, not file content) — used by
/// `FileListView`'s context-menu submenu and the Properties dialog's
/// "Изменить…" button.
///
/// `nonisolated`: a namespace of pure `NSWorkspace` wrappers shouldn't
/// inherit the project's default main-actor isolation — without this,
/// calling `displayName(for:)` through `Optional.map` (a generic,
/// non-isolated-by-default API) from inside a `@ViewBuilder` triggers a
/// cross-actor-hop warning even though the call site is itself on MainActor.
nonisolated enum OpenWithPicker {
    static func availableApplications(for url: URL) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: url)
    }

    static func defaultApplication(for url: URL) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: url)
    }

    static func displayName(for appURL: URL) -> String {
        FileManager.default.displayName(atPath: appURL.path)
    }

    static func open(_ url: URL, with appURL: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Changes the default app for just this one file.
    static func setDefaultApplication(_ appURL: URL, forFile url: URL, completion: @escaping @Sendable (Error?) -> Void = { _ in }) {
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenFileAt: url, completion: completion)
    }

    /// Changes the default app for every file of this content type.
    static func setDefaultApplication(_ appURL: URL, forType contentType: UTType, completion: @escaping @Sendable (Error?) -> Void = { _ in }) {
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: contentType, completion: completion)
    }
}

/// `Menu`/list content enumerating every app that can open `item`, with the
/// current default marked — matching Explorer's "Open with" submenu.
/// Defaults to actually opening the file on selection; pass `onSelect` to
/// repurpose the same list for picking a new default application instead.
struct OpenWithMenuContent: View {
    let item: FileSystemItem
    var onSelect: ((URL) -> Void)?

    var body: some View {
        let appURLs = OpenWithPicker.availableApplications(for: item.url)
        let defaultAppURL = OpenWithPicker.defaultApplication(for: item.url)
        ForEach(appURLs, id: \.self) { appURL in
            Button(OpenWithPicker.displayName(for: appURL) + (appURL == defaultAppURL ? " (по умолчанию)" : "")) {
                if let onSelect {
                    onSelect(appURL)
                } else {
                    OpenWithPicker.open(item.url, with: appURL)
                }
            }
        }
    }
}
