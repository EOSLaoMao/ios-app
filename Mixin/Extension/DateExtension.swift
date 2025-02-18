import Foundation

extension DateFormatter {

    static let dateFull = DateFormatter(dateFormat: "yyyy-MM-dd HH:mm:ss")
    static let yyyymmdd = DateFormatter(dateFormat: "yyyyMMdd")
    static let date = DateFormatter(dateFormat: "MMM d, yyyy")

    static let month = DateFormatter(dateFormat: R.string.localizable.date_format_month())
    static let dayDate = DateFormatter(dateFormat: R.string.localizable.date_format_day())
    static let weekDate = DateFormatter(dateFormat: "EEEE")
    static let dateSimple = DateFormatter(dateFormat: R.string.localizable.date_format_date())
    static let nameOfTheDayAndTime = DateFormatter(dateFormat: "EEEE, " + R.string.localizable.date_format_day())
    static let dateAndTime = DateFormatter(dateFormat: R.string.localizable.date_format_date() + " " + R.string.localizable.date_format_day())
}

extension Date {

    func timeAgo() -> String {
        let now = Date()
        let nowDateComponents = Calendar.current.dateComponents([.day], from: now)
        let dateComponents = Calendar.current.dateComponents([.day], from: self)
        let days = Date().timeIntervalSince(self) / 86400
        if days < 1 && nowDateComponents.day == dateComponents.day {
            return DateFormatter.dayDate.string(from: self)
        } else if days < 7 {
            return DateFormatter.weekDate.string(from: self).capitalized
        } else {
            return DateFormatter.dateSimple.string(from: self)
        }
    }

    func timeDayAgo() -> String {
        let now = Date()
        let nowDateComponents = Calendar.current.dateComponents([.day, .month, .year, .weekOfYear], from: now)
        let dateComponents = Calendar.current.dateComponents([.day, .month, .year, .weekOfYear], from: self)

        if nowDateComponents.day == dateComponents.day && nowDateComponents.year == dateComponents.year && nowDateComponents.month == dateComponents.month {
            return R.string.localizable.chat_time_today()
        } else {
            if nowDateComponents.year == dateComponents.year && nowDateComponents.weekOfYear == dateComponents.weekOfYear {
                return DateFormatter.weekDate.string(from: self)
            } else if nowDateComponents.year == dateComponents.year {
                return DateFormatter.month.string(from: self)
            } else {
                return DateFormatter.date.string(from: self)
            }
        }
    }

    func timeHoursAndMinutes() -> String {
        return DateFormatter.dayDate.string(from: self)
    }
}

extension TimeInterval {
    
    static let oneDay: TimeInterval = 24 * 60 * 60
    
}
