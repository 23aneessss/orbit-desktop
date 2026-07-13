import Foundation

enum OrbitDate {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }()

    static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func key(_ date: Date = .now) -> String {
        keyFormatter.string(from: calendar.startOfDay(for: date))
    }

    static func date(daysFromToday days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: .now)) ?? .now
    }

    static func greeting(name: String) -> String {
        let hour = calendar.component(.hour, from: .now)
        let prefix: String
        switch hour {
        case 0..<5: prefix = "Up late"
        case 5..<12: prefix = "Good morning"
        case 12..<18: prefix = "Good afternoon"
        default: prefix = "Good evening"
        }
        return name.isEmpty ? prefix : "\(prefix), \(name)"
    }
}

