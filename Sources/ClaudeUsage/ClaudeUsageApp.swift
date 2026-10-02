import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
	private var controller: StatusItemController?

	static func main() {
		let delegate = AppDelegate()
		NSApplication.shared.delegate = delegate
		withExtendedLifetime(delegate) {
			NSApplication.shared.run()
		}
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		controller = StatusItemController()
	}
}
