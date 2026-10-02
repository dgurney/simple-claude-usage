import AppKit
import ServiceManagement
import SwiftUI

@MainActor
func makeSettingsWindow() -> NSWindow {
	let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
	window.title = "Claude Usage Settings"
	window.styleMask = [.titled, .closable]
	// Reopened from the menu after it's closed.
	window.isReleasedWhenClosed = false
	window.center()
	return window
}

private struct SettingsView: View {
	@State private var openAtLogin = false
	@Environment(\.appearsActive) private var appearsActive

	var body: some View {
		Form {
			Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: setOpenAtLogin))
		}
		.formStyle(.grouped)
		.scrollDisabled(true)
		.fixedSize(horizontal: false, vertical: true)
		.frame(width: 380)
		// The login item can also be changed in System Settings.
		.onChange(of: appearsActive, initial: true) {
			if appearsActive {
				openAtLogin = SMAppService.mainApp.status == .enabled
			}
		}
	}

	private func setOpenAtLogin(_ on: Bool) {
		do {
			if on {
				try SMAppService.mainApp.register()
			} else {
				try SMAppService.mainApp.unregister()
			}
		} catch {
			NSApp.presentError(error)
		}
		openAtLogin = SMAppService.mainApp.status == .enabled
	}
}
