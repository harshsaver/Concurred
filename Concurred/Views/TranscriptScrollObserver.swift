import AppKit
import SwiftUI

/// Pauses following when the user scrolls upward inside the transcript. The native
/// List retains scrolling/virtualization; this view never consumes an input event.
struct TranscriptScrollObserver: NSViewRepresentable {
    var onScrollUp: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.onScrollUp = onScrollUp
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScrollUp = onScrollUp
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        weak var view: NSView?
        var onScrollUp: (() -> Void)?
        private var monitor: Any?

        func start() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let view = self.view, let window = view.window,
                      event.window === window, event.scrollingDeltaY > 0,
                      view.bounds.contains(view.convert(event.locationInWindow, from: nil)) else { return event }
                self.onScrollUp?()
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { stop() }
    }
}
