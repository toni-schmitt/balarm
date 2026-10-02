import Foundation

public enum DurationText {
    /// Spoken-style duration for the header, e.g. "25 min" or "1 hr, 30 min" in English.
    public static func words(seconds: Int, locale: Locale = .autoupdatingCurrent) -> String {
        var calendar = Calendar.current
        calendar.locale = locale
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .short
        formatter.allowedUnits = [.hour, .minute, .second]
        return formatter.string(from: TimeInterval(seconds)) ?? ""
    }

    /// Positional time left: "m:ss" below one hour, "h:mm:ss" from one hour on.
    public static func clock(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = seconds % 3600 / 60
        let secs = seconds % 60
        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(secs))"
        }
        return "\(minutes):\(twoDigits(secs))"
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
