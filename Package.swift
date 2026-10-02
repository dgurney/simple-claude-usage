// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "simple-claude-usage",
	platforms: [.macOS(.v26)],
	targets: [
		.executableTarget(
			name: "ClaudeUsage",
			path: "Sources/ClaudeUsage"),
		.testTarget(
			name: "ClaudeUsageTests",
			dependencies: ["ClaudeUsage"],
			path: "Tests/ClaudeUsageTests"),
	]
)
