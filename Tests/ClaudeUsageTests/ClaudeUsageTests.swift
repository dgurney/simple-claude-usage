import Foundation
import Testing

@testable import ClaudeUsage

private let minute: TimeInterval = 60
private let hour = 60 * minute
private let day = 24 * hour
// Tuesday
private let now = date("2026-09-29T14:00:00Z")
private let utc = TimeZone.gmt
private let us = Locale(identifier: "en_US")
private let uk = Locale(identifier: "en_GB")

private func date(_ text: String) -> Date {
	try! Date.ISO8601FormatStyle(includingFractionalSeconds: text.contains(".")).parse(text)
}

@Test func durations() {
	#expect(formatDuration(42 * minute) == "42m")
	#expect(formatDuration(30) == "1m", "rounds partial minutes up")
	#expect(formatDuration(2 * hour + 14 * minute) == "2h 14m")
	#expect(formatDuration(3 * day + 5 * hour + 59 * minute) == "3d 5h")
}

@Test func clockTimes() {
	#expect(formatClockTime(now + 4 * hour + 30 * minute, now: now, locale: uk, timeZone: utc) == "18:30")
	#expect(formatClockTime(now + 4 * hour + 30 * minute, now: now, locale: us, timeZone: utc) == "6:30\u{202F}PM")
	#expect(formatClockTime(now + 3 * day, now: now, locale: uk, timeZone: utc) == "Fri 14:00")
	#expect(formatClockTime(now + 10 * hour + minute, now: now, locale: uk, timeZone: utc) == "Wed 00:01")
	#expect(
		formatClockTime(now + 8 * hour, now: now, locale: uk, timeZone: TimeZone(identifier: "Europe/Helsinki")!)
			== "Wed 01:00",
		"days are compared in the given time zone")
}

@Test func resets() {
	#expect(formatReset(now + 2 * hour, now: now, locale: uk, timeZone: utc) == "Resets in 2h 0m (16:00)")
	#expect(formatReset(now - minute, now: now) == "Resetting now")
	#expect(formatReset(nil, now: now) == "No reset scheduled")
}

@Test func percentagesAndLevels() {
	#expect(percentLeft(37.4) == 63)
	#expect(percentLeft(112) == 0, "usage past the limit")
	#expect(UsageLevel(percentLeft: 26) == .normal)
	#expect(UsageLevel(percentLeft: 25) == .warning)
	#expect(UsageLevel(percentLeft: 10) == .critical)
}

private let response = Data("""
	{
		"five_hour": {"utilization": 37.0, "resets_at": "2026-09-29T18:30:00.123456+00:00"},
		"seven_day": {"utilization": 12.5, "resets_at": "2026-10-02T09:00:00+00:00"},
		"seven_day_opus": {"utilization": 4, "resets_at": "2026-10-02T09:00:00+00:00"},
		"seven_day_sonnet": {"utilization": 0, "resets_at": null},
		"seven_day_oauth_apps": null,
		"extra_usage": {"is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null},
		"limits": [
			{
				"kind": "session", "group": "five_hour", "percent": 37, "resets_at": "2026-09-29T18:30:00Z",
				"severity": "ok", "is_active": true, "scope": null
			},
			{
				"kind": "session", "group": "five_hour", "percent": 20, "resets_at": "2026-09-29T18:30:00Z",
				"severity": "ok", "is_active": false, "scope": {"model": {"display_name": "Haiku"}}
			},
			{
				"kind": "weekly_scoped", "group": "weekly", "percent": 55, "resets_at": "2026-10-02T09:00:00Z",
				"severity": "ok", "is_active": false, "scope": {"model": {"display_name": "Fable"}}
			}
		]
	}
	""".utf8)

private let session = UsageLimit(
	title: "Current session",
	menuBarLabel: "5h",
	utilization: 37,
	resetsAt: date("2026-09-29T18:30:00.123456Z"))
private let week = UsageLimit(
	title: "Current week (all models)",
	menuBarLabel: "7d",
	utilization: 12.5,
	resetsAt: date("2026-10-02T09:00:00Z"))
private let sonnet = UsageLimit(
	title: "Current week (Sonnet only)",
	menuBarLabel: nil,
	utilization: 0,
	resetsAt: nil)
private let fable = UsageLimit(
	title: "Current week (Fable)",
	menuBarLabel: nil,
	utilization: 55,
	resetsAt: date("2026-10-02T09:00:00Z"))

@Test func usage() throws {
	#expect(try parseUsage(response, subscriptionType: "max") == [session, week, sonnet, fable])
	#expect(try parseUsage(response, subscriptionType: nil) == [session, week, sonnet, fable], "unknown plan")
	#expect(try parseUsage(response, subscriptionType: "pro") == [session, week, fable], "hides the Sonnet limit")
}

@Test func usageSkipsWindowsWithoutUtilization() throws {
	let response = Data("""
		{
			"five_hour": {"utilization": null, "resets_at": null},
			"seven_day": {"utilization": 3, "resets_at": "2026-10-02T09:00:00Z"}
		}
		""".utf8)
	#expect(try parseUsage(response, subscriptionType: "max") == [
		UsageLimit(
			title: "Current week (all models)",
			menuBarLabel: "7d",
			utilization: 3,
			resetsAt: date("2026-10-02T09:00:00Z")),
	])
}

@Test func usageSkipsLimitsWithoutPercentages() throws {
	let response = Data("""
		{
			"seven_day": {"utilization": 3, "resets_at": "2026-10-02T09:00:00Z"},
			"limits": [
				{"kind": "session", "percent": null, "resets_at": null, "scope": null},
				{
					"kind": "weekly_scoped", "percent": null, "resets_at": "2026-10-02T09:00:00Z",
					"scope": {"model": {"display_name": "Fable"}}
				}
			]
		}
		""".utf8)
	#expect(try parseUsage(response, subscriptionType: "pro") == [
		UsageLimit(
			title: "Current week (all models)",
			menuBarLabel: "7d",
			utilization: 3,
			resetsAt: date("2026-10-02T09:00:00Z")),
	])
}

@Test func responseErrors() {
	#expect(responseError(status: 200, retryAfter: nil) == nil)
	#expect(responseError(status: 401, retryAfter: nil) == .signInExpired)
	#expect(responseError(status: 403, retryAfter: nil) == .forbidden)
	#expect(responseError(status: 429, retryAfter: "120") == .rateLimited(retryAfter: 120))
	#expect(responseError(status: 429, retryAfter: nil) == .rateLimited(retryAfter: nil))
	#expect(
		responseError(status: 429, retryAfter: "Wed, 30 Sep 2026 07:28:00 GMT") == .rateLimited(retryAfter: nil),
		"only a number of seconds says how long to wait")
	#expect(responseError(status: 500, retryAfter: nil)?.localizedDescription == "Usage request failed with HTTP 500.")
}

@Test func signIn() throws {
	#expect(
		try parseSignIn(Data("""
			{"claudeAiOauth": {"accessToken": "access", "refreshToken": "refresh", "expiresAt": 1, "subscriptionType": "pro"}}
			""".utf8)) == SignIn(accessToken: "access", subscriptionType: "pro"))
	#expect(
		try parseSignIn(Data("""
			{"claudeAiOauth": {"accessToken": "access", "refreshToken": "refresh", "expiresAt": 1}}
			""".utf8)).subscriptionType == nil,
		"unknown plan")
	#expect(throws: UsageError.notSignedIn, "only other sign-ins") {
		try parseSignIn(Data(#"{"mcpOAuth": {}}"#.utf8))
	}
	#expect(throws: UsageError.notSignedIn, "sign-in emptied after a rejected renewal") {
		try parseSignIn(Data("""
			{"claudeAiOauth": {"accessToken": "", "refreshToken": "", "expiresAt": 0, "subscriptionType": "max"}}
			""".utf8))
	}
}

@Test func serviceStatus() throws {
	let summary = Data("""
		{
			"page": {"id": "tymt9n04zgry", "name": "Claude", "url": "https://status.claude.com"},
			"components": [{"id": "yyzkbfz2thpt", "name": "Claude Code", "status": "partial_outage"}],
			"incidents": [
				{
					"id": "abc123", "name": "Elevated errors on Claude Code", "status": "investigating", "impact": "minor",
					"incident_updates": [{"status": "investigating", "body": "We are investigating."}]
				}
			],
			"scheduled_maintenances": [],
			"status": {"indicator": "minor", "description": "Partial System Outage"}
		}
		""".utf8)
	#expect(try parseServiceStatus(summary) == ServiceStatus(
		indicator: .minor,
		description: "Partial System Outage",
		incidents: ["Elevated errors on Claude Code"]))
}
