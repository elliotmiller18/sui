import AppKit

// Written for Sui by us: use one four-color suit palette throughout the UI.
func suitColoredText(_ text: String, font: NSFont, rankColor: NSColor = .white, dimmed: Bool = false) -> NSAttributedString {
    let result = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: rankColor])
    let palette: [(String, NSColor)] = [("♣", .systemGreen), ("♦", .systemBlue), ("♥", .systemRed), ("♠", .black)]
    let string = text as NSString
    for (symbol, color) in palette {
        var start = 0
        while start < string.length {
            let range = string.range(of: symbol, options: [], range: NSRange(location: start, length: string.length - start))
            guard range.location != NSNotFound else { break }
            result.addAttributes([.foregroundColor: dimmed ? NSColor.disabledControlTextColor : color,
                                  .strokeColor: NSColor.white.withAlphaComponent(dimmed ? 0.15 : 0.9),
                                  .strokeWidth: -3.0], range: range)
            start = NSMaxRange(range)
        }
    }
    return result
}

// Written for Sui by us: share picker card rendering with the board header.
final class CardButton: NSButton {
    var displayOnly = false
    override func hitTest(_ point: NSPoint) -> NSView? { displayOnly ? nil : super.hitTest(point) }
    override var acceptsFirstResponder: Bool { !displayOnly && super.acceptsFirstResponder }
    var selected = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let background = selected ? NSColor.controlAccentColor : NSColor(calibratedWhite: isEnabled ? 0.22 : 0.14, alpha: 1)
        background.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        let text = suitColoredText(title, font: .systemFont(ofSize: 15, weight: .semibold), rankColor: isEnabled ? .white : .disabledControlTextColor, dimmed: !isEnabled)
        let size = text.size()
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).stroke()
        }
    }
}

// A fixed-size sheet; selecting cards never changes the main window's layout.
final class CardPicker: NSObject {
    private let alert = NSAlert()
    private let minimum: Int
    private let maximum: Int
    private var selected: [String]
    private var buttons = [CardButton]()
    private let selectionLabel = NSTextField(labelWithString: "")
    private let deck: [String]

    init(title: String, selected: [String], used: [String], allowed: Set<String>? = nil, minimum: Int, maximum: Int) {
        self.minimum = minimum; self.maximum = maximum; self.selected = selected
        let rows: [(String, String)] = [
            ("s", "♠"), ("h", "♥"),
            ("c", "♣"), ("d", "♦")
        ]
        deck = rows.flatMap { suit in ranks.map { $0 + suit.0 } }
        super.init()
        alert.messageText = title
        alert.informativeText = minimum == maximum ? "Select \(maximum == 1 ? "one card" : "\(maximum) cards"). Used board cards are unavailable." : "Select 3–5 board cards. Click a selected card to remove it."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 228))
        for (row, suit) in rows.enumerated() {
            for (column, rank) in ranks.enumerated() {
                let card = rank + suit.0
                let button = CardButton(frame: NSRect(x: column * 43, y: 44 + (3-row) * 46, width: 40, height: 42))
                button.title = rank + suit.1
                button.setAccessibilityLabel(rank + " of " + ["s": "spades", "h": "hearts", "c": "clubs", "d": "diamonds"][suit.0]!)
                button.isBordered = false; button.setButtonType(.momentaryPushIn)
                button.isEnabled = !used.contains(card) && (allowed?.contains(card) ?? true)
                button.tag = buttons.count; button.target = self; button.action = #selector(selectCard(_:))
                buttons.append(button); content.addSubview(button)
            }
        }
        selectionLabel.frame = NSRect(x: 0, y: 4, width: 560, height: 28)
        selectionLabel.alignment = .center; selectionLabel.font = .systemFont(ofSize: 14, weight: .medium)
        content.addSubview(selectionLabel); alert.accessoryView = content
        refresh()
    }
    @objc private func selectCard(_ sender: NSButton) {
        let card = deck[sender.tag]
        if let index = selected.firstIndex(of: card) { selected.remove(at: index) }
        else if maximum == 1 { selected = [card] }
        else if selected.count < maximum { selected.append(card) }
        refresh()
    }
    private func refresh() {
        for (index, button) in buttons.enumerated() { button.selected = selected.contains(deck[index]) }
        if selected.isEmpty { selectionLabel.stringValue = "No cards selected" }
        else { selectionLabel.attributedStringValue = suitColoredText(selected.map(cardDisplay).joined(separator: "   "), font: .systemFont(ofSize: 14, weight: .medium)) }
        alert.buttons[0].isEnabled = (minimum...maximum).contains(selected.count)
    }
    func present(on window: NSWindow, completion: @escaping ([String]) -> Void) {
        alert.beginSheetModal(for: window) { [self] response in
            if response == .alertFirstButtonReturn { completion(selected) }
        }
    }
}

func cardDisplay(_ card: String) -> String {
    String(card.prefix(1)) + (["s": "♠", "h": "♥", "c": "♣", "d": "♦"][String(card.suffix(1))] ?? "")
}
