import AppKit

// Written for Sui by us: each compact suit cell owns its native hover tooltip.
final class ComboCell: NSView {
    let combo: ComboBreakdown
    let actions: [String]
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 82, height: 82) }
    init(combo: ComboBreakdown, actions: [String]) {
        self.combo = combo; self.actions = actions
        super.init(frame: .zero)
        toolTip = combo.summary(actions: actions)
        setAccessibilityElement(true); setAccessibilityRole(.staticText)
        setAccessibilityLabel(combo.summary(actions: actions))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        NSColor(calibratedWhite: 0.20, alpha: 1).setFill(); path.fill()
        NSGraphicsContext.saveGraphicsState(); path.addClip()
        if combo.status == .available {
            var x = rect.minX
            for (action, frequency) in zip(actions, combo.frequencies) {
                color(action).setFill()
                NSRect(x: x, y: rect.minY, width: rect.width * frequency, height: rect.height).fill()
                x += rect.width * frequency
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let ink: NSColor = combo.status == .available ? .white : .secondaryLabelColor
        let text = suitColoredText(combo.displayName, font: .monospacedSystemFont(ofSize: 15, weight: .semibold), rankColor: ink, dimmed: combo.status != .available)
        let size = text.size()
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        if combo.status == .blocked {
            NSColor.secondaryLabelColor.withAlphaComponent(0.4).setStroke()
            let slash = NSBezierPath(); slash.move(to: NSPoint(x: rect.maxX - 13, y: rect.minY + 4))
            slash.line(to: NSPoint(x: rect.maxX - 4, y: rect.minY + 13)); slash.lineWidth = 1.5; slash.stroke()
        }
    }
}
