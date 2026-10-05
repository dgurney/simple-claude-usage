import AppKit
import SwiftUI

/// The width the menu's own rows are laid out at. They stretch with the menu.
private let rowWidth: CGFloat = 300

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
	private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
	private let monitor = UsageMonitor()
	private let menu = NSMenu()
	/// The plan's name, the rows for the usage limits and the line below them.
	private var usageItems: [NSMenuItem] = []
	private let serviceItem = NSMenuItem()
	private lazy var settingsWindow = makeSettingsWindow()

	override init() {
		super.init()

		serviceItem.action = #selector(openStatusPage)
		serviceItem.target = self
		serviceItem.toolTip = "Open \(statusPageURL.host()!)"
		// The dot's color is the status, so it has to show even where menus
		// otherwise leave out item images.
		if #available(macOS 27, *) {
			serviceItem.preferredImageVisibility = .visible
		}

		menu.delegate = self
		menu.addItem(.separator())
		menu.addItem(.sectionHeader(title: "Claude Status"))
		menu.addItem(serviceItem)
		menu.addItem(.separator())
		let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
		settingsItem.target = self
		menu.addItem(settingsItem)
		menu.addItem(NSMenuItem(
			title: "Quit Claude Usage",
			action: #selector(NSApplication.terminate(_:)),
			keyEquivalent: "q"))
		statusItem.menu = menu

		monitor.onChange = { [unowned self] in render() }
		render()
		monitor.start()
	}

	func menuWillOpen(_ menu: NSMenu) {
		render()
		monitor.refreshIfStale()
	}

	private func render() {
		let now = Date.now
		renderButton()
		// While the menu is open, AppKit loses changes to an item that come
		// after other items are inserted in the same pass.
		renderServiceItem(now: now)

		for item in usageItems {
			menu.removeItem(item)
		}
		usageItems = (monitor.usage?.value.limits ?? []).map { hostingItem(LimitRow(limit: $0, now: now)) }
		usageItems.append(hostingItem(footer(now: now)))
		if let planName = monitor.usage?.value.planName {
			usageItems.insert(.sectionHeader(title: planName), at: 0)
		}
		for (index, item) in usageItems.enumerated() {
			menu.insertItem(item, at: index)
		}
	}

	private func renderButton() {
		let button = statusItem.button!
		let shown = (monitor.usage?.value.limits ?? []).compactMap { limit in
			limit.menuBarLabel.map { (label: $0, percentLeft: percentLeft(limit.utilization), title: limit.title) }
		}

		if shown.isEmpty {
			let symbol = monitor.error == nil
				? "gauge.open.with.lines.needle.33percent"
				: "gauge.open.with.lines.needle.84percent.exclamation"
			button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
			button.attributedTitle = NSAttributedString()
			button.appearsDisabled = monitor.usage == nil && monitor.error == nil
			button.setAccessibilityLabel(monitor.error == nil ? "Claude Usage" : "Claude Usage: couldn't fetch usage")
			return
		}

		let fontSize = NSFont.menuBarFont(ofSize: 0).pointSize
		let labelAttributes: [NSAttributedString.Key: Any] = [
			.font: NSFont.systemFont(ofSize: fontSize - 2, weight: .medium),
			// The menu bar draws secondaryLabelColor as an opaque gray that can
			// vanish into the wallpaper, so dim the label color instead. The color
			// is resolved when drawn so it follows the menu bar's light or dark text.
			.foregroundColor: NSColor(name: nil) { _ in NSColor.labelColor.withAlphaComponent(0.6) },
		]
		let title = NSMutableAttributedString()
		for (index, limit) in shown.enumerated() {
			if index > 0 {
				title.append(NSAttributedString(string: "  "))
			}
			title.append(NSAttributedString(string: "\(limit.label) ", attributes: labelAttributes))
			var percentAttributes: [NSAttributedString.Key: Any] = [
				.font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
			]
			percentAttributes[.foregroundColor] = UsageLevel(percentLeft: limit.percentLeft).menuBarColor
			title.append(NSAttributedString(string: "\(limit.percentLeft)%", attributes: percentAttributes))
		}
		button.image = nil
		button.attributedTitle = title
		// Like the menu, the menu bar keeps showing the last usage when a refresh fails.
		button.appearsDisabled = monitor.error != nil
		button.setAccessibilityLabel(
			"Claude Usage: " + shown.map { "\($0.title), \($0.percentLeft)% left" }.joined(separator: "; ")
				+ (monitor.error == nil ? "" : " (not up to date)"))
	}

	private func footer(now: Date) -> UsageFooter {
		if monitor.isRenewing {
			return UsageFooter(kind: .progress, text: "Renewing the Claude Code sign-in…")
		}
		if let error = monitor.error {
			return UsageFooter(kind: .warning, text: errorText(error, now: now))
		}
		guard let usage = monitor.usage else {
			return UsageFooter(kind: .progress, text: "Loading…")
		}
		if usage.value.limits.isEmpty {
			return UsageFooter(kind: .info, text: "No usage limits reported")
		}
		return UsageFooter(kind: .info, text: "Updated \(formatClockTime(usage.date, now: now))")
	}

	private func errorText(_ error: any Error, now: Date) -> String {
		var text = error is UsageError
			? error.localizedDescription
			: "Couldn't fetch usage. \(error.localizedDescription)"
		if let retryAt = monitor.retryAt(now: now) {
			text += " Trying again at \(formatClockTime(retryAt, now: now))."
		}
		if let usage = monitor.usage {
			text += " Showing usage from \(formatClockTime(usage.date, now: now))."
		}
		return text
	}

	private func renderServiceItem(now: Date) {
		let status = monitor.serviceStatus
		var details = status?.value.incidents ?? []
		if let error = monitor.serviceError {
			details.append(error.localizedDescription)
			if let status {
				details.append("Showing the status from \(formatClockTime(status.date, now: now)).")
			}
		}

		if let status {
			serviceItem.title = status.value.description
		} else {
			serviceItem.title = monitor.serviceError == nil
				? "Checking the Claude status…"
				: "Couldn't check the Claude status"
		}
		serviceItem.subtitle = details.isEmpty ? nil : details.joined(separator: "\n")
		let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .regular)
			.applying(.init(paletteColors: [status?.value.indicator.color ?? .systemGray]))
		serviceItem.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)!
			.withSymbolConfiguration(configuration)
	}

	private func hostingItem(_ view: some View) -> NSMenuItem {
		let height = NSHostingController(rootView: view)
			.sizeThatFits(in: CGSize(width: rowWidth, height: .greatestFiniteMagnitude))
			.height
		let hostingView = NSHostingView(rootView: view)
		hostingView.frame.size = CGSize(width: rowWidth, height: height)
		hostingView.autoresizingMask = .width
		let item = NSMenuItem()
		item.view = hostingView
		return item
	}

	@objc private func openStatusPage() {
		NSWorkspace.shared.open(statusPageURL)
	}

	@objc private func openSettings() {
		// The app has no Dock icon, so the window would otherwise open behind other apps.
		NSApp.activate()
		settingsWindow.makeKeyAndOrderFront(nil)
	}
}

private extension UsageLevel {
	var menuBarColor: NSColor? {
		switch self {
		case .normal: nil
		case .warning: .systemOrange
		case .critical: .systemRed
		}
	}
}

private extension ServiceStatus.Indicator {
	var color: NSColor {
		switch self {
		case .operational: .systemGreen
		case .minor: .systemYellow
		case .major: .systemOrange
		case .critical: .systemRed
		case .maintenance: .systemBlue
		}
	}
}
