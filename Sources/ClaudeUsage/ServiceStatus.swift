import Foundation

let statusPageURL = URL(string: "https://status.claude.com")!
private let summaryURL = statusPageURL.appending(path: "api/v2/summary.json")

struct ServiceStatus: Equatable {
	enum Indicator: String, Decodable {
		case operational = "none"
		case minor, major, critical, maintenance
	}

	let indicator: Indicator
	let description: String
	/// The names of the unresolved incidents.
	let incidents: [String]
}

struct StatusRequestError: LocalizedError {
	let status: Int

	var errorDescription: String? { "Status request failed with HTTP \(status)." }
}

func fetchServiceStatus(session: URLSession) async throws -> ServiceStatus {
	let (data, response) = try await session.data(from: summaryURL)
	let status = (response as! HTTPURLResponse).statusCode
	guard status == 200 else {
		throw StatusRequestError(status: status)
	}
	return try parseServiceStatus(data)
}

func parseServiceStatus(_ data: Data) throws -> ServiceStatus {
	struct Summary: Decodable {
		struct Status: Decodable {
			let indicator: ServiceStatus.Indicator
			let description: String
		}
		struct Incident: Decodable {
			let name: String
		}

		let status: Status
		let incidents: [Incident]
	}

	let summary = try JSONDecoder().decode(Summary.self, from: data)
	return ServiceStatus(
		indicator: summary.status.indicator,
		description: summary.status.description,
		incidents: summary.incidents.map(\.name))
}
