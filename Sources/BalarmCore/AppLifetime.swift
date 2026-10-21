/// Decides when Balarm quits on its own: once it has neither its window nor an alarm. An alarm
/// outlives a closed window in the menu bar until it ends.
public struct AppLifetime: Sendable {
    private var hasWindowOpened = false

    public init() {}

    /// Called whenever whether an alarm exists or the window is open may have changed; returns
    /// whether to quit.
    public mutating func shouldQuit(hasAlarm: Bool, isWindowOpen: Bool) -> Bool {
        if isWindowOpen { hasWindowOpened = true }
        // At launch, this can be asked before the window has opened.
        guard hasWindowOpened else { return false }
        guard !hasAlarm else { return false }
        return !isWindowOpen
    }
}
