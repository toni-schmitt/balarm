import AppKit
import SwiftUI

/// Reports the alarm window becoming visible or not and closing, from AppKit. Only AppKit tells
/// whether it is visible: hidden, on another Space or covered by other windows, it stays open
/// but is not. Closing stops a ringing alarm, so it comes from AppKit's notice that the window
/// closes, which means nothing else, rather than from SwiftUI's `onDisappear`.
struct AlarmWindowTracker: NSViewRepresentable {
    var onVisibilityChange: (Bool) -> Void
    var onClose: () -> Void

    func makeNSView(context: Context) -> TrackerView {
        TrackerView(onVisibilityChange: onVisibilityChange, onClose: onClose)
    }

    func updateNSView(_ view: TrackerView, context: Context) {}

    final class TrackerView: NSView {
        private let onVisibilityChange: (Bool) -> Void
        private let onClose: () -> Void
        private var observers: [any NSObjectProtocol] = []

        init(onVisibilityChange: @escaping (Bool) -> Void, onClose: @escaping () -> Void) {
            self.onVisibilityChange = onVisibilityChange
            self.onClose = onClose
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { return nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// SwiftUI keeps this view in the same window when it opens the window again, so the
        /// observers stay in place across closing and reopening.
        override func viewDidMoveToWindow() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let visibilityChanges: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
            ]
            for name in visibilityChanges {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.scheduleVisibilityReport() }
                })
            }
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onClose() }
            })
            scheduleVisibilityReport()
        }

        /// Reported once the current update is done, since a notice can arrive while SwiftUI
        /// updates the window and the report changes state that SwiftUI observes.
        private func scheduleVisibilityReport() {
            Task { [weak self] in self?.reportVisibility() }
        }

        private func reportVisibility() {
            guard let window else { return }
            // `isVisible` is false once the window has closed, also for a report queued before.
            let isOnScreen = window.isVisible && window.occlusionState.contains(.visible)
            // A minimized window's Dock tile keeps showing its content.
            onVisibilityChange(isOnScreen || window.isMiniaturized)
        }
    }
}
