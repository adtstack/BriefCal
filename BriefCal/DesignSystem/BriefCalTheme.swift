import SwiftUI

enum BriefCalTheme {
    static let accent = Color(red: 0.17, green: 0.44, blue: 0.60)
    static let accentSoft = Color(red: 0.17, green: 0.44, blue: 0.60).opacity(0.12)
    static let calendarRail = Color(red: 0.24, green: 0.57, blue: 0.69)
    static let subtleDivider = Color.primary.opacity(0.09)
    static let mutedText = Color.secondary

    static func calendarColor(
        _ color: CalendarColor?,
        accountType: CalendarAccountType
    ) -> Color {
        guard let color else {
            return accountType == .exchange
                ? calendarRail
                : Color.secondary.opacity(0.65)
        }
        return Color(
            .sRGB,
            red: color.red,
            green: color.green,
            blue: color.blue,
            opacity: color.alpha
        )
    }
}
