import Foundation

/// Converts an ISO-8601 timestamp (with fractional seconds + Z) to a user-friendly string.
func formatDate(_ dateString: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
    formatter.locale = Locale(identifier: "en_US_POSIX")

    guard let date = formatter.date(from: dateString) else { return dateString }

    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

/// Gives a relative description such as “Just now”, “5m ago”, “2h ago”, “3d ago”.
func formatRelativeDate(_ dateString: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
    formatter.locale = Locale(identifier: "en_US_POSIX")

    guard let date = formatter.date(from: dateString) else { return dateString }

    let interval = Date().timeIntervalSince(date)

    switch interval {
    case ..<60:                     return "Just now"
    case ..<3600:                   return "\(Int(interval/60))m ago"
    case ..<86_400:                 return "\(Int(interval/3600))h ago"
    default:                        return "\(Int(interval/86_400))d ago"
    }
}
