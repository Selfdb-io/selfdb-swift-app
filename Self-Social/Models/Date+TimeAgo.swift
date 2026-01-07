//
//  Date+TimeAgo.swift
//  Self-Social
//

import Foundation

extension String {
    func timeAgo() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = formatter.date(from: self) else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: self) else { return self }
            return date.timeAgoDisplay()
        }

        return date.timeAgoDisplay()
    }
}

extension Date {
    func timeAgoDisplay() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
