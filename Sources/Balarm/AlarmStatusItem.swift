import AppKit
import BalarmCore

/// The alarm in the menu bar while one exists, like a timer's Live Activity: an icon for
/// its state and the time left, with a menu for the countdown's actions.
@MainActor
final class AlarmStatusItem: NSObject, NSMenuDelegate {
    private let controller: AlarmController
    /// Made once and only shown or hidden: a hidden item keeps its place in the menu bar, while
    /// a removed and recreated one lands somewhere else among the other items.
    private lazy var statusItem = makeStatusItem()
    private var shownSymbol: String?
    private var isMenuOpen = false

    init(controller: AlarmController) {
        self.controller = controller
    }

    func show(_ countdown: Countdown?, at now: ContinuousClock.Instant) {
        guard let countdown else {
            hide()
            return
        }
        if shownSymbol == nil { statusItem.isVisible = true }
        guard let button = statusItem.button else { return }
        let symbol = symbolName(for: countdown)
        if symbol != shownSymbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            shownSymbol = symbol
            // Running, paused and ringing offer different actions.
            if isMenuOpen, let menu = statusItem.menu { rebuild(menu) }
        }
        let secondsLeft = countdown.displaySeconds(at: now)
        button.title = DurationText.clock(seconds: secondsLeft)
        // Without it, VoiceOver has only the title to read: digits that do not say what they count.
        button.setAccessibilityLabel(accessibilityLabel(for: countdown, secondsLeft: secondsLeft))
    }

    private func makeStatusItem() -> NSStatusItem {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "alarm"
        statusItem.button?.imagePosition = .imageLeading
        // Fixed-width digits keep the item steady while the seconds tick.
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: size, weight: .regular)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        return statusItem
    }

    private func hide() {
        guard shownSymbol != nil else { return }
        statusItem.menu?.cancelTracking()
        statusItem.isVisible = false
        shownSymbol = nil
    }

    private func symbolName(for countdown: Countdown) -> String {
        if countdown.isRinging { return "bell.and.waves.left.and.right.fill" }
        return countdown.isPaused ? "pause.fill" : "timer"
    }

    private func accessibilityLabel(for countdown: Countdown, secondsLeft: Int) -> String {
        if countdown.isRinging { return "Alarm ringing" }
        let state = countdown.isPaused ? "Alarm paused" : "Alarm running"
        return "\(state), \(DurationText.words(seconds: secondsLeft)) left"
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    /// Built as it opens and again when the alarm's state changes while it is open.
    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let countdown = controller.countdown else { return }

        menu.addItem(.sectionHeader(title: summary(of: countdown)))
        if countdown.isRinging {
            menu.addItem(menuItem("Stop", action: #selector(stop)))
            menu.addItem(menuItem("Repeat", action: #selector(repeatAlarm)))
        } else {
            menu.addItem(menuItem(countdown.isPaused ? "Resume" : "Pause", action: #selector(togglePause)))
            menu.addItem(menuItem("Restart…", action: #selector(restart)))
            menu.addItem(menuItem("Cancel Alarm", action: #selector(stop)))
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("Show Balarm", action: #selector(showWindow)))
    }

    private func summary(of countdown: Countdown) -> String {
        let duration = DurationText.words(seconds: countdown.totalSeconds)
        if countdown.isRinging { return "\(duration) · Time's up" }
        if countdown.isPaused { return "\(duration) · Paused" }
        let ringsAt = Date.now.addingTimeInterval(countdown.remaining(at: .now) / .seconds(1))
        return "\(duration) · Rings at \(ringsAt.formatted(.dateTime.hour().minute()))"
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    @objc private func togglePause() { controller.togglePause() }
    @objc private func restart() { controller.requestRestartInWindow() }
    @objc private func stop() { controller.stop() }
    @objc private func repeatAlarm() { controller.repeatAlarm() }
    @objc private func showWindow() { controller.showWindow() }
}
