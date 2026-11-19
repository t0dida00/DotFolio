import Foundation

/// Very short "how long ago", minutes at the finest: Now, 5m, 5h, 1d, 1w, 1mth, 1yrs.
/// Anything under a minute reads as "Now".
public enum CompactAge {
    /// Labels showing this only need refreshing every 15 minutes.
    public static let refreshInterval: TimeInterval = 15 * 60

    public static func string(since date: Date, now: Date = .now) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        let minute = 60, hour = 3_600, day = 86_400, week = 7 * day, month = 30 * day, year = 365 * day
        switch seconds {
        case ..<minute: return "Now"
        case ..<hour: return "\(seconds / minute)m"
        case ..<day: return "\(seconds / hour)h"
        case ..<week: return "\(seconds / day)d"
        case ..<month: return "\(seconds / week)w"
        case ..<year: return "\(seconds / month)mth"
        default: return "\(seconds / year)yrs"
        }
    }
}
