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
		// Never shown, as the app has no menu bar, but lets ⌘W close the settings window.
		let windowMenu = NSMenu()
		windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
		let windowItem = NSMenuItem()
		windowItem.submenu = windowMenu
		let mainMenu = NSMenu()
		mainMenu.addItem(windowItem)
		NSApp.mainMenu = mainMenu
		controller = StatusItemController()
	}
}
