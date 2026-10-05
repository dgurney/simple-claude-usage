import Foundation

private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
/// The login keychain item where Claude Code keeps its sign-in.
private let keychainService = "Claude Code-credentials"
/// `security` exits with this when there is no such item.
private let itemNotFoundStatus: Int32 = 44

/// Longer than Claude Code's own 30s limit on its token request, so a renewal
/// is never killed after the server has issued new tokens but before they are saved.
private let renewalTimeoutSeconds = 60

/// Claude Code only shows the Sonnet limit on these plans; on the others it
/// matches the weekly limit. nil means the plan is unknown.
private let plansWithSonnetLimit: [String?] = ["max", "team", nil]

struct SignIn: Equatable {
	let accessToken: String
	/// nil when the plan is unknown
	let subscriptionType: String?
	/// The plan's usage tier, e.g. "default_claude_max_5x", or nil when unknown.
	let rateLimitTier: String?

	/// The plan's name, as Claude Code shows it plus the Max tier or Team
	/// premium seat, or nil when the plan is unknown.
	var planName: String? {
		switch (subscriptionType, rateLimitTier) {
		case ("max", "default_claude_max_5x"): "Claude Max 5x"
		case ("max", "default_claude_max_20x"): "Claude Max 20x"
		case ("max", _): "Claude Max"
		case ("pro", _): "Claude Pro"
		case ("team", "default_claude_max_5x"): "Claude Team (Premium seat)"
		case ("team", _): "Claude Team"
		case ("enterprise", _): "Claude Enterprise"
		default: nil
		}
	}
}

struct Usage: Equatable {
	/// nil when the plan is unknown
	let planName: String?
	let limits: [UsageLimit]
}

struct UsageLimit: Equatable {
	let title: String
	/// The short label for the menu bar, or nil for limits not shown there.
	let menuBarLabel: String?
	/// The percentage used.
	let utilization: Double
	let resetsAt: Date?
}

/// An error whose message is fit to show to the user as-is.
enum UsageError: LocalizedError, Equatable {
	case notSignedIn
	case signInExpired
	case forbidden
	/// retryAfter is nil when the server didn't say how long to wait.
	case rateLimited(retryAfter: TimeInterval?)
	case httpStatus(Int)

	var errorDescription: String? {
		switch self {
		case .notSignedIn:
			"Claude Code is not signed in. Run `claude` to sign in."
		case .signInExpired:
			"The Claude Code sign-in has expired. Run `claude` to renew it."
		case .forbidden:
			"This Claude Code sign-in isn't allowed to read usage. Try signing in again with `claude auth login`."
		case .rateLimited:
			"Claude is limiting how often usage can be checked."
		case .httpStatus(let status):
			"Usage request failed with HTTP \(status)."
		}
	}
}

/// `security` couldn't read the keychain for a reason other than there being no sign-in.
struct KeychainError: LocalizedError {
	/// What `security` printed about it.
	let message: String

	var errorDescription: String? { message }
}

enum RenewalError: Error {
	case timedOut
	/// The shell couldn't find or run `claude`.
	case claudeNotRun(status: Int32)
}

/// Reads the sign-in from the login keychain through `security`, as Claude Code
/// does. The item was created by that tool, so only it can read the item
/// without macOS asking for permission.
func readSignIn() async throws -> SignIn {
	let process = Process()
	process.executableURL = URL(filePath: "/usr/bin/security")
	process.arguments = ["find-generic-password", "-a", NSUserName(), "-s", keychainService, "-w"]
	let output = Pipe()
	let errors = Pipe()
	process.standardOutput = output
	process.standardError = errors
	let exit = try start(process)

	let data = try await readAll(output)
	// Only ever a line, so reading it after the output can't leave `security` stuck.
	let message = String(decoding: try await readAll(errors), as: UTF8.self)
	for await _ in exit {}

	switch process.terminationStatus {
	case 0:
		return try parseSignIn(data)
	case itemNotFoundStatus:
		throw UsageError.notSignedIn
	case let status:
		let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
		// Empty when `security` was killed.
		throw KeychainError(message: message.isEmpty ? "security exited with status \(status)." : message)
	}
}

private func readAll(_ pipe: Pipe) async throws -> Data {
	var data = Data()
	for try await byte in pipe.fileHandleForReading.bytes {
		data.append(byte)
	}
	return data
}

func parseSignIn(_ data: Data) throws -> SignIn {
	struct Credentials: Decodable {
		struct OAuth: Decodable {
			let accessToken: String
			let refreshToken: String
			let subscriptionType: String?
			let rateLimitTier: String?
		}

		let claudeAiOauth: OAuth?
	}

	// The item also holds other sign-ins, e.g. for MCP servers. Claude Code
	// empties the tokens when the server rejects a renewal.
	guard let oauth = try JSONDecoder().decode(Credentials.self, from: data).claudeAiOauth,
		!oauth.refreshToken.isEmpty
	else {
		throw UsageError.notSignedIn
	}
	return SignIn(
		accessToken: oauth.accessToken,
		subscriptionType: oauth.subscriptionType,
		rateLimitTier: oauth.rateLimitTier)
}

/// Returns the error for an unsuccessful response, or nil for a successful one.
func responseError(status: Int, retryAfter: String?) -> UsageError? {
	switch status {
	case 200: nil
	case 401: .signInExpired
	case 403: .forbidden
	case 429: .rateLimited(retryAfter: retryAfter.flatMap(TimeInterval.init))
	default: .httpStatus(status)
	}
}

func fetchUsage(for signIn: SignIn, session: URLSession) async throws -> Usage {
	var request = URLRequest(url: usageURL)
	request.setValue("Bearer \(signIn.accessToken)", forHTTPHeaderField: "Authorization")
	request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

	let (data, response) = try await session.data(for: request)
	let http = response as! HTTPURLResponse
	if let error = responseError(status: http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After")) {
		throw error
	}
	return Usage(planName: signIn.planName, limits: try parseUsage(data, subscriptionType: signIn.subscriptionType))
}

/// Has Claude Code renew its sign-in. `claude doctor` renews an expired sign-in
/// the same way Claude Code does during normal use, including locking against
/// other Claude Code processes. The app never exchanges tokens itself, as
/// Claude Code may issue a new refresh token and retire the old one.
func renewSignIn() async throws {
	let process = Process()
	// Apps don't get the PATH the user's terminal has, so `claude` is looked up
	// by an interactive login shell, which sets that PATH up.
	process.executableURL = URL(filePath: String(cString: getpwuid(getuid())!.pointee.pw_shell))
	process.arguments = ["-l", "-i", "-c", "exec claude doctor"]
	// doctor reads the settings in its working directory.
	process.currentDirectoryURL = .homeDirectory
	process.standardInput = FileHandle.nullDevice
	process.standardOutput = FileHandle.nullDevice
	process.standardError = FileHandle.nullDevice
	let exit = try start(process)

	let pid = process.processIdentifier
	let timeout = Task {
		do {
			try await Task.sleep(for: .seconds(renewalTimeoutSeconds))
		} catch {
			return false
		}
		kill(pid, SIGKILL)
		return true
	}
	for await _ in exit {}
	timeout.cancel()
	if await timeout.value {
		throw RenewalError.timedOut
	}
	// The shell exits with these when it can't find or run `claude`. doctor's
	// own exit status reports its health checks, not the renewal: the next
	// usage request shows whether the renewal worked.
	if process.terminationReason == .exit, [126, 127].contains(process.terminationStatus) {
		throw RenewalError.claudeNotRun(status: process.terminationStatus)
	}
}

/// Starts `process` and returns a stream that finishes when it exits.
private func start(_ process: Process) throws -> AsyncStream<Void> {
	let (exit, continuation) = AsyncStream.makeStream(of: Void.self)
	process.terminationHandler = { _ in continuation.finish() }
	try process.run()
	return exit
}

func parseUsage(_ data: Data, subscriptionType: String?) throws -> [UsageLimit] {
	struct Window: Decodable {
		let utilization: Double?
		let resetsAt: Date?
	}
	struct Limit: Decodable {
		struct Scope: Decodable {
			struct Model: Decodable {
				let displayName: String
			}

			let model: Model?
		}

		let kind: String
		let percent: Double?
		let resetsAt: Date?
		let scope: Scope?
	}
	struct Response: Decodable {
		let fiveHour: Window?
		let sevenDay: Window?
		let sevenDaySonnet: Window?
		let limits: [Limit]?
	}

	let decoder = JSONDecoder()
	decoder.keyDecodingStrategy = .convertFromSnakeCase
	decoder.dateDecodingStrategy = .iso8601
	let response = try decoder.decode(Response.self, from: data)

	var windows: [(window: Window?, title: String, menuBarLabel: String?)] = [
		(response.fiveHour, "Current session", "5h"),
		(response.sevenDay, "Current week (all models)", "7d"),
	]
	if plansWithSonnetLimit.contains(subscriptionType) {
		windows.append((response.sevenDaySonnet, "Current week (Sonnet only)", nil))
	}

	var limits = windows.compactMap { window, title, menuBarLabel -> UsageLimit? in
		guard let window, let utilization = window.utilization else {
			return nil
		}
		return UsageLimit(title: title, menuBarLabel: menuBarLabel, utilization: utilization, resetsAt: window.resetsAt)
	}
	for limit in response.limits ?? [] where limit.kind == "weekly_scoped" {
		if let model = limit.scope?.model, let percent = limit.percent {
			limits.append(UsageLimit(
				title: "Current week (\(model.displayName))",
				menuBarLabel: nil,
				utilization: percent,
				resetsAt: limit.resetsAt))
		}
	}
	return limits
}
