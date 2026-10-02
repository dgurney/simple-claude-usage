import Foundation
import os

private let refreshInterval: TimeInterval = 5 * 60
private let refreshOnOpenAfter: TimeInterval = 60
private let httpTimeout: TimeInterval = 15
private let renewalCooldown: TimeInterval = 5 * 60
/// In case the server rejected a token that is still valid.
private let rejectedTokenRetryInterval: TimeInterval = 60 * 60

private let logger = Logger(subsystem: "dev.gurney.claude-usage", category: "usage")

struct Fetched<Value> {
	let value: Value
	let date: Date
}

/// Keeps the usage limits and the Claude status up to date.
@MainActor
final class UsageMonitor {
	private(set) var usage: Fetched<[UsageLimit]>?
	/// Why the latest usage refresh failed.
	private(set) var error: (any Error)?
	private(set) var isRenewing = false
	private(set) var serviceStatus: Fetched<ServiceStatus>?
	/// Why the latest status check failed.
	private(set) var serviceError: (any Error)?

	/// Called whenever any of the above changes.
	var onChange: () -> Void = {}

	private let session: URLSession
	private var isRefreshing = false
	private var isCheckingService = false
	private var lastRenewalAt = Date.distantPast
	/// The access token the server last rejected or rate limited, which isn't
	/// sent again until `until`.
	private var blocked: (token: String, until: Date, error: UsageError)?

	init() {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.timeoutIntervalForRequest = httpTimeout
		session = URLSession(configuration: configuration)
	}

	func start() {
		refresh()
		refreshServiceStatus()
		let timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { _ in
			MainActor.assumeIsolated {
				self.refresh()
				self.refreshServiceStatus()
			}
		}
		timer.tolerance = 30
	}

	/// Refreshes whatever was last fetched more than a minute ago.
	func refreshIfStale() {
		if isStale(usage?.date) {
			refresh()
		}
		if isStale(serviceStatus?.date) {
			refreshServiceStatus()
		}
	}

	/// When the usage request that was rate limited will be tried again.
	func retryAt(now: Date) -> Date? {
		guard let blocked, case .rateLimited = blocked.error, blocked.error == error as? UsageError, blocked.until > now
		else {
			return nil
		}
		return blocked.until
	}

	private func isStale(_ date: Date?) -> Bool {
		guard let date else {
			return true
		}
		return Date.now.timeIntervalSince(date) > refreshOnOpenAfter
	}

	private func refresh() {
		// A renewal ends with a refresh of its own.
		guard !isRenewing, !isRefreshing else {
			return
		}
		isRefreshing = true
		Task {
			do {
				usage = Fetched(value: try await fetch(), date: .now)
				error = nil
			} catch {
				if !(error is UsageError) {
					logger.error("Couldn't fetch usage: \(String(describing: error), privacy: .public)")
				}
				self.error = error
			}
			isRefreshing = false
			onChange()
		}
	}

	private func fetch() async throws -> [UsageLimit] {
		let signIn = try await readSignIn()
		if let blocked, signIn.accessToken == blocked.token, Date.now < blocked.until {
			if blocked.error == .signInExpired {
				renewIfDue()
			}
			throw blocked.error
		}

		do {
			return try await fetchUsage(for: signIn, session: session)
		} catch let error as UsageError {
			switch error {
			case .signInExpired:
				blocked = (signIn.accessToken, .now + rejectedTokenRetryInterval, error)
				renewIfDue()
			case .rateLimited(let retryAfter?):
				blocked = (signIn.accessToken, .now + retryAfter, error)
			default:
				break
			}
			throw error
		}
	}

	private func renewIfDue() {
		guard Date.now.timeIntervalSince(lastRenewalAt) >= renewalCooldown else {
			return
		}
		lastRenewalAt = .now
		isRenewing = true
		Task {
			do {
				try await renewSignIn()
			} catch {
				logger.error("Couldn't renew the sign-in: \(String(describing: error), privacy: .public)")
			}
			isRenewing = false
			refresh()
		}
	}

	private func refreshServiceStatus() {
		guard !isCheckingService else {
			return
		}
		isCheckingService = true
		Task {
			do {
				serviceStatus = Fetched(value: try await fetchServiceStatus(session: session), date: .now)
				serviceError = nil
			} catch {
				logger.error("Couldn't check the Claude status: \(String(describing: error), privacy: .public)")
				serviceError = error
			}
			isCheckingService = false
			onChange()
		}
	}
}
