/// The keys Balarm reacts to.
public enum AlarmKey: Equatable, Sendable {
    case digit(Int)
    case delete
    case enter
    case escape
    case space
    case repeatAlarm

    /// Holding a digit or Delete types or erases repeatedly; every other key acts once per press.
    public var isRepeatable: Bool {
        switch self {
        case .digit, .delete: true
        case .enter, .escape, .space, .repeatAlarm: false
        }
    }
}
