import Foundation

func formatDuration(_ interval: TimeInterval) -> String {
	let totalMinutes = Int((interval / 60).rounded(.up))
	let days = totalMinutes / (24 * 60)
	let hours = totalMinutes / 60 % 24
	let minutes = totalMinutes % 60

	if days > 0 {
		return "\(days)d \(hours)h"
	}
	if hours > 0 {
		return "\(hours)h \(minutes)m"
	}
	return "\(minutes)m"
}

/// Formats a time as just the clock time when it falls on the same day as
/// `now`, or with the weekday too otherwise.
func formatClockTime(
	_ time: Date,
	now: Date,
	locale: Locale = .autoupdatingCurrent,
	timeZone: TimeZone = .autoupdatingCurrent
) -> String {
	var calendar = locale.calendar
	calendar.timeZone = timeZone
	let clock = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).hour().minute()
	return time.formatted(calendar.isDate(time, inSameDayAs: now) ? clock : clock.weekday(.abbreviated))
}

func formatReset(
	_ resetsAt: Date?,
	now: Date,
	locale: Locale = .autoupdatingCurrent,
	timeZone: TimeZone = .autoupdatingCurrent
) -> String {
	guard let resetsAt else {
		return "No reset scheduled"
	}
	if resetsAt <= now {
		return "Resetting now"
	}
	let clock = formatClockTime(resetsAt, now: now, locale: locale, timeZone: timeZone)
	return "Resets in \(formatDuration(resetsAt.timeIntervalSince(now))) (\(clock))"
}

/// Usage can go past 100% when extra usage is enabled.
func percentLeft(_ utilization: Double) -> Int {
	max(0, 100 - Int(utilization.rounded()))
}

enum UsageLevel {
	case normal, warning, critical

	init(percentLeft: Int) {
		if percentLeft <= 10 {
			self = .critical
		} else if percentLeft <= 25 {
			self = .warning
		} else {
			self = .normal
		}
	}
}
