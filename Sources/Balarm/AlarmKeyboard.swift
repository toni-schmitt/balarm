import AppKit
import BalarmCore
import SwiftUI

/// A key monitor instead of SwiftUI focus: typing must work the moment the window appears,
/// without first clicking into it. It handles only keys aimed at the alarm window, so the
/// restart prompt and the duration editor, which are sheets with windows of their own,
/// keep their keys; holding Return, Esc, Space or R is ignored after the first press in
/// every window.
struct AlarmKeyboard: NSViewRepresentable {
    var onKey: (AlarmKey) -> Bool

    func makeNSView(context: Context) -> MonitorView {
        MonitorView(onKey: onKey)
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onKey = onKey
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) {
        view.removeMonitor()
    }

    final class MonitorView: NSView {
        var onKey: (AlarmKey) -> Bool
        private var monitor: Any?

        init(onKey: @escaping (AlarmKey) -> Bool) {
            self.onKey = onKey
            super.init(frame: .zero)
            focusRingType = .none
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard let key = AlarmKey(event) else { return event }
                // A held Return must not stop the ringing and then start another alarm.
                // Checked before the window: a held R opens the restart prompt, and its
                // repeats, which then go to the prompt, must not beep there.
                guard !event.isARepeat || key.isRepeatable else { return nil }
                guard let window else { return event }
                guard event.window === window else { return event }
                // A sheet may slide in or out while the alarm window is still key.
                guard window.attachedSheet == nil else { return event }
                return onKey(key) ? nil : event
            }
        }

        required init?(coder: NSCoder) { return nil }

        /// With keyboard navigation turned on in System Settings, AppKit focused the
        /// window's first control each time it showed the window, drawing a focus ring
        /// around the duration display. Clearing the focus before that did not stop it,
        /// and clearing it after left the display focused for a moment. As the window's
        /// initial first responder, this view takes that focus instead and draws no ring.
        /// Typing reaches the monitor whatever has focus.
        override func viewDidMoveToWindow() {
            window?.initialFirstResponder = self
        }

        // AppKit gives the initial focus only to a view that accepts it.
        override var acceptsFirstResponder: Bool { true }

        // Out of the Tab order, so Tab moves between the controls only.
        override var canBecomeKeyView: Bool { false }

        // Only here for its window and lifetime; clicks belong to the content above it,
        // and dragging the window by its background must keep working.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func removeMonitor() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
