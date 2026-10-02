import SwiftUI

/// Lines the rows' contents up with the titles of the menu's own items.
private let rowInset: CGFloat = 16

struct LimitRow: View {
	let limit: UsageLimit
	let now: Date

	var body: some View {
		let left = percentLeft(limit.utilization)
		VStack(alignment: .leading, spacing: 6) {
			HStack(alignment: .firstTextBaseline) {
				Text(limit.title)
					.fontWeight(.semibold)
				Spacer()
				Text("\(left)% left")
					.monospacedDigit()
					.foregroundStyle(.secondary)
			}
			UsageBar(fraction: Double(left) / 100, tint: UsageLevel(percentLeft: left).color)
			Text(formatReset(limit.resetsAt, now: now))
				.font(.subheadline)
				.foregroundStyle(.secondary)
		}
		.padding(.vertical, 3)
		.menuRow()
		.accessibilityElement(children: .combine)
	}
}

/// A capsule filled as far as the usage left.
private struct UsageBar: View {
	let fraction: Double
	let tint: Color

	private let height: CGFloat = 6

	var body: some View {
		GeometryReader { geometry in
			Capsule()
				.fill(tint)
				// Never narrower than it is tall, which would squash the rounded ends.
				.frame(width: fraction > 0 ? max(geometry.size.width * fraction, height) : 0)
		}
		.frame(height: height)
		.background(.quaternary, in: Capsule())
		.accessibilityHidden(true)
	}
}

struct UsageFooter: View {
	enum Kind {
		case info, progress, warning
	}

	let kind: Kind
	/// Markdown, for the commands that messages name.
	let text: String

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: 6) {
			switch kind {
			case .info:
				EmptyView()
			case .progress:
				ProgressView()
					.controlSize(.mini)
					.alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
			case .warning:
				Image(systemName: "exclamationmark.triangle.fill")
					.symbolRenderingMode(.multicolor)
			}
			// Any text is valid inline Markdown.
			Text(try! AttributedString(
				markdown: text,
				options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
				.fixedSize(horizontal: false, vertical: true)
		}
		.font(.subheadline)
		.foregroundStyle(.secondary)
		.menuRow()
	}
}

extension UsageLevel {
	var color: Color {
		switch self {
		case .normal: .accentColor
		case .warning: .orange
		case .critical: .red
		}
	}
}

private extension View {
	func menuRow() -> some View {
		padding(.horizontal, rowInset)
			.padding(.vertical, 4)
			.frame(maxWidth: .infinity, alignment: .leading)
	}
}
