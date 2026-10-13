import AppKit
import QuickLookUI
import SwiftUI

/// Inline Quick Look preview of a single file, wrapping AppKit's
/// `QLPreviewView`.
///
/// Deliberately not the SwiftUI `.quickLookPreview` modifier or
/// `QLPreviewPanel` — both present a floating panel/window rather than
/// embedding inline, and `.quickLookPreview` is documented to log
/// "panel has no controller" errors on macOS. `QLPreviewView` is the
/// AppKit class actually meant for embedding Quick Look inside a view
/// hierarchy.
struct PreviewPaneView: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)
        view?.autostarts = true
        return view ?? QLPreviewView()
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        guard context.coordinator.lastURL != url else { return }
        context.coordinator.lastURL = url
        nsView.previewItem = url as NSURL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastURL: URL?
    }
}
