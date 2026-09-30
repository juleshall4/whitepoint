import Foundation

struct SolarLocation: Codable {
    let latitude: Double
    let longitude: Double
    var isValid: Bool { latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 }
}

enum ScheduleEvent: String, Codable, CaseIterable {
    case time, sunset, sunrise
    var title: String { switch self { case .time: return "Time"; case .sunset: return "Sunset"; case .sunrise: return "Sunrise" } }
}

struct ScheduleEndpoint: Codable {
    var event: ScheduleEvent
    var minute: Int
}

struct ScheduleSettings: Codable {
    var mode = "manual"
    var on = ScheduleEndpoint(event: .sunset, minute: 20 * 60)
    var off = ScheduleEndpoint(event: .sunrise, minute: 7 * 60)
    var location: SolarLocation?

    static func load(_ defaults: UserDefaults) -> ScheduleSettings {
        guard let data = defaults.data(forKey: "schedule"), let settings = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return settings
    }
    func save(_ defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "schedule") }
    }
    var needsLocation: Bool { on.event != .time || off.event != .time }
}

struct ScheduleTransition {
    let date: Date
    let enabled: Bool
}

struct ScheduleEvaluation {
    let enabled: Bool?
    let next: ScheduleTransition?
    let issue: String?
}

// NOAA's fractional-year equations; apparent horizon at -0.833 degrees.
func solarEvent(on day: Date, location: SolarLocation, sunrise: Bool, calendar: Calendar) -> Date? {
    guard location.isValid else { return nil }
    let components = calendar.dateComponents([.year, .month, .day], from: day)
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(secondsFromGMT: 0)!
    guard let midnight = utc.date(from: components),
          let dayNumber = utc.ordinality(of: .day, in: .year, for: midnight),
          let daysInYear = utc.range(of: .day, in: .year, for: midnight)?.count else { return nil }
    let gamma = 2 * Double.pi / Double(daysInYear) * Double(dayNumber - 1)
    let equation = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma) - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
    let declination = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma) - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma) - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
    let latitude = location.latitude * .pi / 180
    let cosine = cos(90.833 * .pi / 180) / (cos(latitude) * cos(declination)) - tan(latitude) * tan(declination)
    guard cosine.isFinite, abs(cosine) <= 1 else { return nil }
    let angle = acos(cosine) * 180 / .pi
    let minutes = 720 - 4 * (location.longitude + (sunrise ? angle : -angle)) - equation
    let estimate = midnight.addingTimeInterval(minutes * 60)
    // Longitude and civil time zones can place the UTC event on an adjacent day.
    for offset in -1...1 {
        let candidate = estimate.addingTimeInterval(Double(offset) * 86400)
        if calendar.isDate(candidate, inSameDayAs: day) { return candidate }
    }
    return nil
}

func evaluateSchedule(_ settings: ScheduleSettings, now: Date, calendar: Calendar) -> ScheduleEvaluation {
    if settings.needsLocation && settings.location?.isValid != true {
        return ScheduleEvaluation(enabled: nil, next: nil, issue: "Set a location for sunrise and sunset.")
    }
    if settings.on.event == settings.off.event && (settings.on.event != .time || settings.on.minute == settings.off.minute) {
        return ScheduleEvaluation(enabled: nil, next: nil, issue: "On and off must use different times or solar events.")
    }
    let start = calendar.startOfDay(for: now)
    var transitions: [ScheduleTransition] = []
    for offset in -2...2 {
        guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
        for (endpoint, enabled) in [(settings.on, true), (settings.off, false)] {
            let date: Date?
            switch endpoint.event {
            case .time:
                guard (0..<1440).contains(endpoint.minute) else { return ScheduleEvaluation(enabled: nil, next: nil, issue: "Choose a valid time.") }
                date = calendar.date(bySettingHour: endpoint.minute / 60, minute: endpoint.minute % 60, second: 0, of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
            case .sunrise, .sunset:
                date = solarEvent(on: day, location: settings.location!, sunrise: endpoint.event == .sunrise, calendar: calendar)
            }
            guard let date else { return ScheduleEvaluation(enabled: nil, next: nil, issue: "No sunrise or sunset near this date. Use fixed times here.") }
            transitions.append(ScheduleTransition(date: date, enabled: enabled))
        }
    }
    transitions.sort { $0.date == $1.date ? (!$0.enabled && $1.enabled) : $0.date < $1.date }
    for index in 1..<transitions.count where abs(transitions[index].date.timeIntervalSince(transitions[index - 1].date)) < 1 {
        return ScheduleEvaluation(enabled: nil, next: nil, issue: "On and off coincide. Choose different times.")
    }
    return ScheduleEvaluation(enabled: transitions.last(where: { $0.date <= now })?.enabled,
                              next: transitions.first(where: { $0.date > now }), issue: nil)
}
