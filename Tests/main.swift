import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ description: String) {
    guard condition() else { print("FAIL: \(description)"); exit(1) }
    checks += 1
}
func calendar(_ zone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: zone)!; return calendar
}
func date(_ string: String, calendar: Calendar) -> Date {
    let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"; return formatter.date(from: string)!
}
let london = calendar("Europe/London")
var fixed = ScheduleSettings()
fixed.mode = "scheduled"; fixed.on = ScheduleEndpoint(event: .time, minute: 20 * 60); fixed.off = ScheduleEndpoint(event: .time, minute: 7 * 60)
for (clock, expected) in [("06:59", true), ("07:00", false), ("19:59", false), ("20:00", true), ("23:59", true), ("00:01", true)] {
    let result = evaluateSchedule(fixed, now: date("2026-09-30 \(clock)", calendar: london), calendar: london)
    check(result.enabled == expected && result.issue == nil, "overnight boundary at \(clock)")
    check(result.next!.date > date("2026-09-30 \(clock)", calendar: london), "next boundary is in the future")
}
var daytime = fixed; daytime.on.minute = 9 * 60; daytime.off.minute = 17 * 60
for (clock, expected) in [("08:59", false), ("09:00", true), ("16:59", true), ("17:00", false)] {
    check(evaluateSchedule(daytime, now: date("2026-09-30 \(clock)", calendar: london), calendar: london).enabled == expected, "daytime boundary at \(clock)")
}
var invalid = fixed; invalid.off.minute = invalid.on.minute
check(evaluateSchedule(invalid, now: Date(), calendar: london).issue != nil, "identical times rejected")
let utc = calendar("UTC")
var dst = fixed; dst.on.minute = 90; dst.off.minute = 7 * 60
// UK clocks skip 01:30 on March 29: use the next valid time, 02:00 BST (01:00 UTC).
check(evaluateSchedule(dst, now: date("2026-03-29 00:59", calendar: utc), calendar: london).enabled == false, "DST gap before adjusted on time")
check(evaluateSchedule(dst, now: date("2026-03-29 01:00", calendar: utc), calendar: london).enabled == true, "DST gap advances to next valid time")
// On the repeated October hour, the first 01:30 is used; both instances stay on.
check(evaluateSchedule(dst, now: date("2026-10-25 00:30", calendar: utc), calendar: london).enabled == true, "first repeated hour boundary")
check(evaluateSchedule(dst, now: date("2026-10-25 01:15", calendar: utc), calendar: london).enabled == true, "repeated hour stays on")
var solar = ScheduleSettings(); solar.mode = "scheduled"
check(evaluateSchedule(solar, now: Date(), calendar: london).issue != nil, "solar schedule requires a location")
solar.location = SolarLocation(latitude: 51.4779, longitude: 0)
let day = date("2026-09-30 12:00", calendar: london)
let sunrise = solarEvent(on: day, location: solar.location!, sunrise: true, calendar: london)!
let sunset = solarEvent(on: day, location: solar.location!, sunrise: false, calendar: london)!
let formatter = DateFormatter(); formatter.timeZone = london.timeZone; formatter.dateFormat = "HH:mm"
print("Greenwich solar estimates: sunrise \(formatter.string(from: sunrise)), sunset \(formatter.string(from: sunset)).")
// US Naval Observatory one-day API, Greenwich, 2026-09-30, UTC+1:
// apparent sunrise 06:59 and sunset 18:40. This local NOAA approximation has a five-minute tolerance.
check(abs(sunrise.timeIntervalSince(date("2026-09-30 06:59", calendar: london))) < 300, "solar sunrise agrees with independent USNO fixture")
check(abs(sunset.timeIntervalSince(date("2026-09-30 18:40", calendar: london))) < 300, "solar sunset agrees with independent USNO fixture")
check(evaluateSchedule(solar, now: day, calendar: london).enabled == false, "solar schedule off at midday")
check(evaluateSchedule(solar, now: sunset.addingTimeInterval(1), calendar: london).enabled == true, "solar schedule on after sunset")
check(evaluateSchedule(solar, now: sunrise.addingTimeInterval(-1), calendar: london).enabled == true, "solar schedule on before sunrise")
check(evaluateSchedule(solar, now: sunrise, calendar: london).enabled == false, "solar schedule off at sunrise")
solar.on = ScheduleEndpoint(event: .time, minute: 20 * 60)
check(evaluateSchedule(solar, now: date("2026-09-30 21:00", calendar: london), calendar: london).enabled == true, "mixed fixed-on sunrise-off")
solar.location = SolarLocation(latitude: 89, longitude: 0)
check(evaluateSchedule(solar, now: date("2026-06-21 12:00", calendar: london), calendar: london).issue != nil, "polar date reports missing solar event")
check(!SolarLocation(latitude: .nan, longitude: 0).isValid && !SolarLocation(latitude: 91, longitude: 0).isValid, "invalid coordinates rejected")
let auckland = calendar("Pacific/Auckland")
let aucklandDay = date("2026-01-01 12:00", calendar: auckland)
let aucklandSunrise = solarEvent(on: aucklandDay, location: SolarLocation(latitude: -36.85, longitude: 174.76), sunrise: true, calendar: auckland)!
check(auckland.isDate(aucklandSunrise, inSameDayAs: aucklandDay), "sunrise stays on civil date across UTC date line")
let suite = UserDefaults(suiteName: "local.julian.WhitePoint.ScheduleTests")!
suite.removePersistentDomain(forName: "local.julian.WhitePoint.ScheduleTests")
fixed.save(suite)
let loaded = ScheduleSettings.load(suite)
check(loaded.mode == fixed.mode && loaded.on.minute == fixed.on.minute && loaded.off.event == fixed.off.event, "schedule survives save and reload")
suite.removePersistentDomain(forName: "local.julian.WhitePoint.ScheduleTests")
print("PASS: \(checks) schedule checks.")
