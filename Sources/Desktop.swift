import AppKit

func color(_ label: String) -> NSColor {
    let text = label.lowercased()
    if text.contains("unassigned") { return NSColor(calibratedWhite: 0.20, alpha: 1) }
    if text.contains("fold") { return NSColor(calibratedRed: 0.27, green: 0.40, blue: 0.58, alpha: 1) }
    // Written for Sui by us: a limp is a passive action, distinct from a raise.
    if text.contains("call") || text.contains("check") || text.contains("limp") { return NSColor(calibratedRed: 0.18, green: 0.58, blue: 0.46, alpha: 1) }
    if text.contains("all-in") { return NSColor(calibratedRed: 0.65, green: 0.23, blue: 0.45, alpha: 1) }
    // Written for Sui by us: progressively deeper reds identify postflop sizes.
    for (size, rgb) in [("1/4 pot", [0.98, 0.60, 0.58]), ("1/3 pot", [0.94, 0.44, 0.42]), ("2/3 pot", [0.87, 0.28, 0.29]), ("3/4 pot", [0.78, 0.20, 0.25]), ("3x pot", [0.37, 0.05, 0.12]), ("1.5x pot", [0.49, 0.08, 0.16]), ("pot", [0.69, 0.15, 0.21])] {
        if text.hasPrefix("bet \(size) ·") || text.hasPrefix("raise \(size) ·") {
            return NSColor(calibratedRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
        }
    }
    return NSColor(calibratedRed: 0.85, green: 0.39, blue: 0.29, alpha: 1)
}
// Written for Sui by us: a horizontally scrolling, colored record of the hand.
final class ActionHistoryStrip: NSView {
    var onStreet: ((String) -> Void)?
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        var x: CGFloat = 0
        for group in groups {
            let width = groupWidth(group)
            if point.x >= x && point.x < x + width { onStreet?(group.street); return }
            x += width
        }
    }
    private var groups = [(street: String, board: [String], actions: [HandHistoryAction])]()
    override var isFlipped: Bool { true }
    private func groupWidth(_ group: (street: String, board: [String], actions: [HandHistoryAction])) -> CGFloat {
        let title = group.street.uppercased() + "  " + group.board.map(cardDisplay).joined(separator: " ")
        let titleWidth = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold)]).width
        return max(CGFloat(group.actions.count) * 80 - 6, titleWidth) + 18
    }
    func show(_ actions: [HandHistoryAction]) {
        groups = []
        for action in actions {
            if let last = groups.indices.last, groups[last].street == action.street, groups[last].board == action.board {
                groups[last].actions.append(action)
            } else { groups.append((action.street, action.board, [action])) }
        }
        frame = NSRect(x: 0, y: 0, width: max(1, groups.reduce(CGFloat(0)) { $0 + groupWidth($1) }), height: 74)
        needsDisplay = true
        let description = actions.map { action -> String in
            let detail = action.action.lowercased().contains("bb") || action.amountText.isEmpty ? action.action : action.action + " · " + action.amountText
            return [action.street, action.seat, detail].joined(separator: " · ")
        }.joined(separator: "\n")
        toolTip = description
        setAccessibilityElement(true); setAccessibilityLabel("Hand history. " + description)
    }
    override func draw(_ dirtyRect: NSRect) {
        var x: CGFloat = 0
        for group in groups {
            let title = group.street.uppercased() + "  " + group.board.map(cardDisplay).joined(separator: " ")
            suitColoredText(title, font: .systemFont(ofSize: 10, weight: .semibold), rankColor: .secondaryLabelColor).draw(at: NSPoint(x: x, y: 0))
            for (index, action) in group.actions.enumerated() {
                let rect = NSRect(x: x + CGFloat(index) * 80, y: 18, width: 74, height: 52)
                let fill = color(action.action)
                fill.setFill(); NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
                let rgb = fill.usingColorSpace(.deviceRGB) ?? fill
                let light = rgb.redComponent * 0.2126 + rgb.greenComponent * 0.7152 + rgb.blueComponent * 0.0722 > 0.62
                let ink: NSColor = light ? .black : .white
                let lines: [(String, CGFloat, NSFont)] = [(action.seat, 4, .systemFont(ofSize: 10, weight: .medium)), (action.kind, 19, .systemFont(ofSize: 11, weight: .semibold)), (action.amountText, 34, .monospacedDigitSystemFont(ofSize: 11, weight: .medium))]
                for (text, offset, font) in lines {
                    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
                    let width = (text as NSString).size(withAttributes: attributes).width
                    (text as NSString).draw(at: NSPoint(x: rect.midX - width / 2, y: rect.minY + offset), withAttributes: attributes)
                }
            }
            x += groupWidth(group)
        }
    }
}
// Written for Sui by us: the selected hand mirrors a grid cell; the full range
// uses a proportional bar. Both share the grid's action colors and exact splits.
final class FrequencyView: NSView {
    var actions = [String]()
    var frequencies = [Double]()
    var hand: String?
    var onSuitToggle: (() -> Void)?
    var suitsExpanded = false
    private let suitButton = NSButton(title: "♠", target: nil, action: nil)
    private var unavailable: String?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureSuitButton()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureSuitButton()
    }
    private func configureSuitButton() {
        suitButton.isBordered = false; suitButton.setButtonType(.toggle)
        suitButton.font = .systemFont(ofSize: 16, weight: .semibold)
        suitButton.attributedTitle = suitColoredText("♠", font: .systemFont(ofSize: 16, weight: .semibold))
        suitButton.target = self; suitButton.action = #selector(toggleSuits)
        suitButton.isHidden = true; addSubview(suitButton)
    }
    @objc private func toggleSuits() { onSuitToggle?() }
    override func layout() {
        super.layout()
        suitButton.frame = NSRect(x: 3, y: 62, width: 20, height: 20)
    }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: 260, height: hand == nil ? 28 + CGFloat(actions.count) * 19 : (unavailable == nil ? max(84, CGFloat(actions.count) * 19) : 84))
    }
    func show(actions: [String], frequencies: [Double], hand: String? = nil, unavailable: String? = nil) {
        self.actions = actions; self.frequencies = frequencies; self.hand = hand; self.unavailable = unavailable
        suitButton.isHidden = hand == nil || onSuitToggle == nil
        suitButton.state = suitsExpanded ? .on : .off
        suitButton.toolTip = suitsExpanded ? "Hide suit combinations" : "Show suit combinations"
        suitButton.setAccessibilityLabel((suitsExpanded ? "Hide" : "Show") + " suit combinations for " + (hand ?? ""))
        isHidden = false; invalidateIntrinsicContentSize(); needsDisplay = true
        setAccessibilityElement(true)
        setAccessibilityRole(suitButton.isHidden ? .staticText : .group)
        setAccessibilityChildren(suitButton.isHidden ? [] : [suitButton])
        setAccessibilityLabel((hand ?? "Full range") + ": " + (unavailable ?? zip(actions, frequencies).map { "\($0.0) \(String(format: "%.1f", $0.1 * 100)) percent" }.joined(separator: ", ")))
    }
    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(x: 0, y: 0, width: hand == nil ? bounds.width : 84, height: hand == nil ? 18 : 84)
        NSColor(calibratedWhite: 0.20, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).addClip()
        var x = rect.minX
        for (action, value) in zip(actions, frequencies) {
            color(action).setFill()
            NSRect(x: x, y: rect.minY, width: rect.width * value, height: rect.height).fill()
            x += rect.width * value
        }
        NSGraphicsContext.restoreGraphicsState()
        if let hand = hand {
            let text = suitColoredText(hand, font: .monospacedSystemFont(ofSize: 21, weight: .semibold), dimmed: unavailable != nil)
            let size = text.size()
            text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        }
        if let unavailable = unavailable {
            (unavailable as NSString).draw(in: NSRect(x: 96, y: 25, width: bounds.width - 96, height: 45), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
            return
        }
        let startX: CGFloat = hand == nil ? 0 : 96
        let startY: CGFloat = hand == nil ? 28 : max(0, (84 - CGFloat(actions.count) * 19) / 2)
        for (i, action) in actions.enumerated() {
            guard frequencies.indices.contains(i) else { continue }
            let y = startY + CGFloat(i) * 19
            color(action).setFill(); NSRect(x: startX, y: y + 4, width: 7, height: 7).fill()
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
            (action as NSString).draw(in: NSRect(x: startX + 13, y: y, width: bounds.width - startX - 59, height: 17), withAttributes: attributes)
            let percent = String(format: "%.1f%%", frequencies[i] * 100) as NSString
            let size = percent.size(withAttributes: attributes)
            percent.draw(at: NSPoint(x: bounds.width - size.width, y: y), withAttributes: attributes)
        }
    }
}
final class Grid: NSView {
    var isPreview = false
    var chart: Chart? { didSet { needsDisplay = true } }
    var selected = "AKs" { didSet { needsDisplay = true } }
    var onSelect: ((String) -> Void)?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let chart = chart else { return }
        let w = bounds.width / 13, h = bounds.height / 13
        for (index, hand) in hands.enumerated() {
            let rect = NSRect(x: CGFloat(index % 13) * w + 1, y: CGFloat(index / 13) * h + 1, width: w - 2, height: h - 2)
            NSColor(calibratedWhite: 0.20, alpha: 1).setFill(); rect.fill()
            var x = rect.minX
            for (i, frequency) in chart.frequencies[hand]!.enumerated() {
                color(chart.actions[i]).setFill()
                NSRect(x: x, y: rect.minY, width: rect.width * frequency, height: rect.height).fill()
                x += rect.width * frequency
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: min(14, w / 4), weight: .semibold), .foregroundColor: NSColor.white]
            let text = hand as NSString, size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
            if hand == selected && !isPreview {
                NSColor.white.setStroke(); let path = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1)); path.lineWidth = 2; path.stroke()
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard !isPreview else { return }
        let p = convert(event.locationInWindow, from: nil)
        let row = Int(p.y / (bounds.height / 13)), col = Int(p.x / (bounds.width / 13))
        guard (0..<13).contains(row), (0..<13).contains(col) else { return }
        selected = hands[row * 13 + col]; onSelect?(selected)
    }
}
// Written for Sui by us: a scrolling sidebar starts at Actions at the top.
final class SidebarStack: NSStackView {
    override var isFlipped: Bool { true }
}
final class Desktop: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var root: URL
    let initial: Spot?
    let remainder: String
    let raiseBB: String?
    var preflop: Preflop?
    var postflop: Postflop?
    let streetSolves = StreetSolveHistory()
    let streetNavigation = NSStackView()
    var pendingHandoff: PostflopHandoff?
    let flopSetup = NSStackView()
    var selectedFlop = [String]()
    var solverControl = SolverControl()
    var resettingSolve = false
    var busy = false
    let sidebarScroll = NSScrollView()
    let grid = Grid()
    var progressTimer: Timer?
    let mode = NSPopUpButton()
    // Written for Sui by us: table/rake changes and Reset start a fresh hand.
    let tableSize = NSPopUpButton()
    let stakesPicker = NSPopUpButton()
    let stopNowButton = NSButton(title: "Stop now", target: nil, action: nil)
    let resetButton = NSButton(title: "Reset", target: nil, action: nil)
    let tableOptions = NSStackView()
    let historyPanel = NSStackView()
    let historySeparator = NSBox()
    let historyStrip = ActionHistoryStrip()
    let historyScroll = NSScrollView()
    var historyWidthConstraint: NSLayoutConstraint?
    let toolbarSpacer = NSView()
    let status = NSTextField(labelWithString: "")
    // Written for Sui by us: show board cards using the selector's card tiles.
    let boardCards = NSStackView()
    let detail = NSTextField(wrappingLabelWithString: "")
    let selectedMix = FrequencyView()
    let comboDetails = NSStackView()
    var suitCombosExpanded = false
    let rangeMix = FrequencyView()
    let source = NSTextField(wrappingLabelWithString: "")
    let legend = NSStackView()
    let setup = NSStackView()
    let betSizePicker = NSStackView()
    var betSizeButtons = [NSButton]()
    let storageBudget = NSTextField(string: "")
    let raiseLimitPicker = NSPopUpButton()
    var selectedBoard = [String]()
    let boardButton = NSButton(title: "Choose board…", target: nil, action: nil)
    let pot = NSTextField(string: "6")
    let stack = NSTextField(string: "97.5")
    let ip = NSTextField(string: "")
    let oop = NSTextField(string: "")
    var actionKeys = [String]()
    init(root: URL, spots: [Spot], initial: Spot?, remainder: String, raiseBB: String?, postflop: Postflop? = nil) {
        self.root = root; self.initial = initial; self.remainder = remainder; self.raiseBB = raiseBB; self.postflop = postflop
    }
    func label(_ text: String, size: CGFloat = 13, bold: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular); return field
    }
    func row(_ views: [NSView]) -> NSStackView { let row = NSStackView(views: views); row.spacing = 10; return row }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu(), appItem = NSMenuItem(), appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Sui", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem); NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 850), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Sui"; window.minSize = NSSize(width: 1020, height: 850)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1)
        let content = window.contentView!
        mode.addItems(withTitles: ["Preflop", "Postflop"]); mode.target = self; mode.action = #selector(changeMode)
        for count in stride(from: 9, through: 2, by: -1) {
            tableSize.addItem(withTitle: count == 2 ? "Heads-up (2)" : "\(count) players")
            tableSize.lastItem?.tag = count
        }
        tableSize.selectItem(withTag: 6); tableSize.target = self; tableSize.action = #selector(resetHand)
        stakesPicker.addItems(withTitles: ["NL50", "NL500"])
        stakesPicker.target = self; stakesPicker.action = #selector(resetHand)
        stakesPicker.autoenablesItems = false
        resetButton.target = self; resetButton.action = #selector(resetHand)
        for view in [mode, label("Table"), tableSize, stakesPicker] { tableOptions.addArrangedSubview(view) }
        tableOptions.spacing = 10
        historyScroll.drawsBackground = false; historyScroll.hasHorizontalScroller = true
        historyScroll.autohidesScrollers = true; historyScroll.scrollerStyle = .overlay
        historyScroll.documentView = historyStrip
        historyScroll.heightAnchor.constraint(equalToConstant: 74).isActive = true
        historyPanel.orientation = .vertical; historyPanel.alignment = .leading; historyPanel.spacing = 4
        historyPanel.edgeInsets = NSEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        historyPanel.wantsLayer = true; historyPanel.layer?.cornerRadius = 8
        historyPanel.layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 1).cgColor
        historyPanel.layer?.borderWidth = 1; historyPanel.layer?.borderColor = NSColor.separatorColor.cgColor
        historyPanel.addArrangedSubview(streetNavigation)
        historyPanel.addArrangedSubview(historyScroll)
        historyStrip.onStreet = { [weak self] name in
            let street = ["Preflop": 0, "Flop": 3, "Turn": 4, "River": 5][name]
            if let street = street { self?.rewind(to: street) }
        }
        historyScroll.widthAnchor.constraint(equalTo: historyPanel.widthAnchor, constant: -20).isActive = true
        historyPanel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        historySeparator.boxType = .separator
        historySeparator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        historySeparator.heightAnchor.constraint(equalToConstant: 84).isActive = true
        toolbarSpacer.heightAnchor.constraint(equalToConstant: 1).isActive = true
        stopNowButton.target = self; stopNowButton.action = #selector(stopNow)
        stopNowButton.isHidden = true
        status.maximumNumberOfLines = 2
        let toolbar = row([tableOptions, resetButton, stopNowButton, historySeparator, historyPanel, toolbarSpacer])
        toolbar.alignment = .centerY
        resetButton.widthAnchor.constraint(equalToConstant: 96).isActive = true
        stopNowButton.widthAnchor.constraint(equalToConstant: 96).isActive = true
        historyWidthConstraint = historyPanel.widthAnchor.constraint(equalTo: toolbar.widthAnchor, constant: -117)
        historyPanel.isHidden = true; historySeparator.isHidden = true
        boardButton.target = self; boardButton.action = #selector(chooseBoard)
        pot.widthAnchor.constraint(equalToConstant: 65).isActive = true; stack.widthAnchor.constraint(equalToConstant: 65).isActive = true
        ip.placeholderString = "AA,AKs or a range-file path"; oop.placeholderString = "AA,AKs or a range-file path"
        for field in [ip, oop] { field.widthAnchor.constraint(equalToConstant: 550).isActive = true }
        setup.orientation = .vertical; setup.alignment = .leading; setup.spacing = 8
        setup.addArrangedSubview(row([label("Board"), boardButton, label("Pot (BB)"), pot, label("Effective stack (BB)"), stack]))
        setup.addArrangedSubview(row([label("OOP range"), oop, NSButton(title: "File…", target: self, action: #selector(chooseOOP))]))
        setup.addArrangedSubview(row([label("IP range"), ip, NSButton(title: "File…", target: self, action: #selector(chooseIP))]))
        setup.addArrangedSubview(NSButton(title: "Solve", target: self, action: #selector(startSolve)))
        flopSetup.spacing = 10; flopSetup.alignment = .centerY
        flopSetup.addArrangedSubview(NSButton(title: "Choose flop…", target: self, action: #selector(chooseFlop)))
        flopSetup.isHidden = true
        status.font = .systemFont(ofSize: 17, weight: .semibold)
        // Written for Sui by us: keep card tiles beside the pot and acting seat.
        boardCards.orientation = .horizontal; boardCards.spacing = 3; boardCards.isHidden = true
        let statusRow = row([boardCards, status])
        // Written for Sui by us: choose any number of sizes before the next solve.
        betSizePicker.spacing = 10
        betSizePicker.addArrangedSubview(label("Bet sizes · pot", size: 12, bold: true))
        for (index, size) in PostflopBetSize.allCases.enumerated() {
            let button = NSButton(checkboxWithTitle: size.title, target: nil, action: nil)
            button.tag = index
            button.state = (postflop?.betSizes ?? defaultPostflopBetSizes).contains(size) ? .on : .off
            button.toolTip = "Applies to bets, raises and donks on every street of the next solve. Sizes cap at the remaining stack."
            betSizeButtons.append(button); betSizePicker.addArrangedSubview(button)
        }
        let savedBudget = UserDefaults.standard.double(forKey: "solverStorageBudgetGiB")
        let initialBudget = postflop?.storageBudgetGiB ?? (savedBudget.isFinite && savedBudget > 0 ? savedBudget : defaultSolverStorageBudgetGiB)
        storageBudget.stringValue = String(format: "%.4g", initialBudget)
        storageBudget.widthAnchor.constraint(equalToConstant: 60).isActive = true
        storageBudget.toolTip = "Estimated RAM for solver strategy arrays, not disk space. Total RAM use can be higher."
        betSizePicker.addArrangedSubview(label("RAM budget (GiB)", size: 12))
        betSizePicker.addArrangedSubview(storageBudget)
        raiseLimitPicker.addItems(withTitles: ["0", "1", "2"])
        let savedRaises = UserDefaults.standard.object(forKey: "solverRaiseLimit") as? Int ?? 2
        let initialRaises = postflop?.raiseLimit ?? savedRaises
        raiseLimitPicker.selectItem(at: (0...2).contains(initialRaises) ? initialRaises : 2)
        raiseLimitPicker.toolTip = "Maximum raises per street after the opening bet. At 2: bet → raise → reraise, then call or fold. Applies to every modeled street."
        betSizePicker.addArrangedSubview(label("Re-raises / street", size: 12))
        betSizePicker.addArrangedSubview(raiseLimitPicker)
        let header = NSStackView(views: [toolbar, setup, betSizePicker, statusRow, flopSetup]); header.orientation = .vertical; header.alignment = .leading; header.spacing = 12
        toolbar.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
        legend.orientation = .vertical; legend.alignment = .leading; legend.spacing = 10
        detail.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        source.font = .systemFont(ofSize: 11); source.textColor = .secondaryLabelColor
        selectedMix.isHidden = true; rangeMix.isHidden = true
        comboDetails.orientation = .vertical; comboDetails.alignment = .leading; comboDetails.spacing = 8
        comboDetails.widthAnchor.constraint(equalToConstant: 260).isActive = true
        comboDetails.isHidden = true
        let sidebar = SidebarStack(views: [label("ACTIONS", size: 11, bold: true), legend, label("FULL RANGE", size: 11, bold: true), rangeMix, label("SELECTED HAND", size: 11, bold: true), selectedMix, comboDetails, detail, source])
        sidebar.orientation = .vertical; sidebar.alignment = .leading; sidebar.spacing = 12
        // Written for Sui by us: additional sizes scroll within the existing sidebar.
        sidebarScroll.drawsBackground = false; sidebarScroll.hasVerticalScroller = true
        sidebarScroll.autohidesScrollers = true; sidebarScroll.scrollerStyle = .overlay
        sidebarScroll.documentView = sidebar
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.widthAnchor.constraint(equalTo: sidebarScroll.contentView.widthAnchor).isActive = true
        for v in [header, grid, sidebarScroll] { v.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(v) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 20), header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24), header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 20), grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24), grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            sidebarScroll.topAnchor.constraint(equalTo: grid.topAnchor), sidebarScroll.leadingAnchor.constraint(equalTo: grid.trailingAnchor, constant: 24), sidebarScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24), sidebarScroll.widthAnchor.constraint(equalToConstant: 260), sidebarScroll.bottomAnchor.constraint(equalTo: grid.bottomAnchor)
        ])
        grid.onSelect = { [weak self] _ in self?.updateDetail() }
        selectedMix.onSuitToggle = { [weak self] in
            guard let self = self else { return }
            self.suitCombosExpanded.toggle()
            self.updateDetail()
        }
        if let postflop = postflop {
            let output = URL(fileURLWithPath: postflop.resultPath)
            if let data = try? Data(contentsOf: output.appendingPathComponent("setup.json")),
               let input = try? JSONDecoder().decode(PostflopInput.self, from: data) {
                streetSolves.remember(input, output: output, owned: false)
            }
            mode.selectItem(at: 1); setup.isHidden = true; renderPostflop()
        }
        else if let initial = initial {
            betSizePicker.isHidden = true
            setup.isHidden = true
            stakesPicker.selectItem(at: 1)
            do { show(try chart(initial, remainder: remainder, raiseBB: raiseBB), clickable: false); status.stringValue = "\(initial.position) · Chart preview" }
            catch { showError(error) }
        } else { changeMode() }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func showHistory(_ actions: [HandHistoryAction]) {
        tableOptions.isHidden = busy || postflop != nil || pendingHandoff != nil || !(preflop?.history.isEmpty ?? true)
        historyWidthConstraint?.constant = busy ? -223 : -117
        historyWidthConstraint?.isActive = !actions.isEmpty
        for view in streetNavigation.arrangedSubviews { streetNavigation.removeArrangedSubview(view); view.removeFromSuperview() }
        if !streetSolves.entries.isEmpty {
            for (title, street) in [("Preflop", 0), ("Flop", 3), ("Turn", 4), ("River", 5)] where (street == 0 && (preflop?.finished == true || streetSolves.entries[3] != nil)) || streetSolves.entries[street] != nil {
                let button = NSButton(title: title, target: self, action: #selector(rewindStreet(_:)))
                button.tag = street; button.isEnabled = !busy; streetNavigation.addArrangedSubview(button)
            }
        }
        let visible = !actions.isEmpty || !streetSolves.entries.isEmpty
        historyWidthConstraint?.isActive = visible
        historyPanel.isHidden = !visible
        historySeparator.isHidden = !visible
        toolbarSpacer.isHidden = visible
        historyStrip.show(actions)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.historyPanel.isHidden else { return }
            self.window.contentView?.layoutSubtreeIfNeeded()
            let x = max(0, self.historyStrip.frame.width - self.historyScroll.contentSize.width)
            self.historyScroll.contentView.scroll(to: NSPoint(x: x, y: 0))
            self.historyScroll.reflectScrolledClipView(self.historyScroll.contentView)
        }
    }
    // Written for Sui by us: reuse the exact tile size, suit colors and drawing from the picker.
    func showBoard(_ cards: [String]) {
        for view in boardCards.arrangedSubviews { boardCards.removeArrangedSubview(view); view.removeFromSuperview() }
        for card in cards {
            let tile = CardButton()
            tile.title = cardDisplay(card); tile.displayOnly = true; tile.isBordered = false
            tile.widthAnchor.constraint(equalToConstant: 40).isActive = true
            tile.heightAnchor.constraint(equalToConstant: 42).isActive = true
            boardCards.addArrangedSubview(tile)
        }
        boardCards.isHidden = cards.isEmpty
    }
    func clear() {
        grid.chart = nil; detail.stringValue = ""; setSource(""); actionKeys = []
        selectedMix.isHidden = true; rangeMix.isHidden = true; comboDetails.isHidden = true
        for view in legend.arrangedSubviews { legend.removeArrangedSubview(view); view.removeFromSuperview() }
    }
    func show(_ chart: Chart, clickable: Bool = true) {
        clear(); grid.chart = chart
        let breakdown = chart.actionBreakdown
        rangeMix.show(actions: chart.actions, frequencies: breakdown)
        for (index, action) in chart.actions.enumerated() {
            let dot = label("■", size: 18); dot.textColor = color(action)
            let button = NSButton(title: action, target: self, action: #selector(selectAction(_:)))
            button.tag = index; button.isEnabled = clickable; button.bezelStyle = .rounded
            legend.addArrangedSubview(row([dot, button]))
        }
        setSource(clickable ? "" : chart.source + "\n\n" + chart.note)
        source.toolTip = chart.source + "\n\n" + chart.note
        updateDetail()
    }
    func setSource(_ text: String) {
        source.stringValue = text
        source.isHidden = text.isEmpty
    }
    func showError(_ error: Error) { clear(); setSource(String(describing: error)) }
    @objc func resetHand() {
        if busy {
            resettingSolve = true
            resetButton.title = "Cancelling…"
            resetButton.isEnabled = false
            stopNowButton.isEnabled = false
            status.stringValue = "Stopping solver…"
            solverControl.cancel()
            return
        }
        mode.selectItem(at: 0)
        selectedFlop = []; selectedBoard = []; boardButton.title = "Choose board…"
        changeMode()
    }
    @objc func changeMode() {
        guard !busy else { return }
        streetSolves.reset()
        suitCombosExpanded = false
        // Written for Sui by us: clear the previous board when starting a new flow.
        showBoard([])
        postflop = nil; preflop = nil; pendingHandoff = nil; flopSetup.isHidden = true; clear()
        betSizePicker.isHidden = mode.indexOfSelectedItem == 0
        setup.isHidden = mode.indexOfSelectedItem == 0
        showHistory([])
        if mode.indexOfSelectedItem == 0 {
            let players = tableSize.selectedItem?.tag ?? 6
            stakesPicker.item(at: 1)?.isEnabled = players == 6
            stakesPicker.item(at: 1)?.toolTip = "The existing NL500 pack covers 6 players only."
            if players != 6 { stakesPicker.selectItem(at: 0) }
            let stakes = stakesPicker.titleOfSelectedItem ?? "NL50"
            do {
                let library = stakes == "NL500" ? root : root.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("preflop")
                preflop = try Preflop(root: library, players: players, stakes: stakes)
                renderPreflop()
            }
            catch { status.stringValue = "Preflop"; showError(error) }
        } else { status.stringValue = "Postflop · Heads-up"; setSource("Enter both ranges and a board, then pick bet sizes. Sizes cap at all-in. No rake.") }
    }
    func renderPreflop() {
        guard let preflop = preflop else { return }
        showHistory(preflop.actionHistory)
        status.stringValue = preflop.message
        do {
            if let current = try preflop.currentChart() { show(current); actionKeys = current.actions }
            else {
                clear()
                if preflop.ending != nil { pendingHandoff = nil; flopSetup.isHidden = true; return }
                let handoff = try preflop.handoff()
                pendingHandoff = handoff
                mode.selectItem(at: 1); betSizePicker.isHidden = false; setup.isHidden = true; flopSetup.isHidden = false
                selectedFlop = []
                status.stringValue = "Postflop · \(handoff.oopSeat) vs \(handoff.ipSeat) · Pot \(String(format: "%.2f", handoff.pot)) BB · Stack \(String(format: "%.2f", handoff.stack)) BB"
                setSource("Choose the flop to continue this hand.\n\nPot, stacks and both ranges are carried forward. Postflop uses no rake.")
            }
        } catch { showError(error) }
    }
    func renderPostflop() {
        guard let postflop = postflop else { return }
        // Written for Sui by us: board ranks/suits are rendered as tiles, not plain text.
        showHistory(postflop.actionHistory)
        betSizePicker.isHidden = !postflop.needsCard
        showBoard(postflop.board)
        status.stringValue = "Pot \(String(format: "%.2f", postflop.pot)) BB · \(postflop.actor)"
        do {
            if let ending = postflop.ending { clear(); status.stringValue = ending; return }
            if postflop.needsCard {
                guard !postflop.nextCards.isEmpty else {
                    betSizePicker.isHidden = true
                    clear(); status.stringValue = "No hands reach this line"
                    setSource("The selected actions have zero frequency for every remaining hand.")
                    return
                }
                clear()
                legend.addArrangedSubview(NSButton(title: postflop.board.count == 3 ? "Choose turn…" : "Choose river…", target: self, action: #selector(dealCard)))
                setSource("Choose bet sizes for the next street, then choose the next board card.")
            } else if let current = try postflop.currentChart() { show(current); actionKeys = postflop.actions; setSource(postflop.convergence); source.toolTip = current.source + "\n" + current.note + "\n" + postflop.resultPath }
        } catch { showError(error) }
    }
    @objc func selectAction(_ sender: NSButton) {
        guard !busy, actionKeys.indices.contains(sender.tag) else { return }
        do {
            if let postflop = postflop { try postflop.advance(actionKeys[sender.tag]); renderPostflop() }
            else if let preflop = preflop { try preflop.advance(actionKeys[sender.tag]); renderPreflop() }
        } catch { showError(error) }
    }
    @objc func chooseBoard() {
        guard !busy else { return }
        CardPicker(title: "Choose board", selected: selectedBoard, used: [], minimum: 3, maximum: 5).present(on: window) { [weak self] cards in
            self?.selectedBoard = cards
            self?.boardButton.title = cards.map(cardDisplay).joined(separator: " ")
        }
    }
    @objc func chooseFlop() {
        guard !busy, pendingHandoff != nil else { return }
        CardPicker(title: "Choose flop", selected: selectedFlop, used: [], minimum: 3, maximum: 3).present(on: window) { [weak self] cards in
            self?.selectedFlop = cards; self?.continueToFlop()
        }
    }
    @objc func dealCard() {
        guard !busy, let postflop = postflop, postflop.needsCard else { return }
        CardPicker(title: postflop.board.count == 3 ? "Choose turn" : "Choose river", selected: [], used: postflop.board,
                   allowed: Set(postflop.nextCards), minimum: 1, maximum: 1).present(on: window) { [weak self] cards in
            guard let self = self, !self.busy, let card = cards.first else { return }
            do { try self.beginSolve(postflop.nextStreetInput(card), nextStreet: true) }
            catch {
                self.renderPostflop()
                self.setSource(String(describing: error))
            }
        }
    }
    func updateDetail() {
        guard let current = grid.chart, let values = current.frequencies[grid.selected] else { return }
        selectedMix.suitsExpanded = suitCombosExpanded
        selectedMix.show(actions: current.actions, frequencies: values, hand: grid.selected)
        comboDetails.isHidden = !suitCombosExpanded
        if suitCombosExpanded { showSuitCombinations(current, hand: grid.selected) }
        detail.isHidden = values.reduce(0, +) > 0
        detail.stringValue = detail.isHidden ? "" : "Outside current range"
    }
    func showSuitCombinations(_ chart: Chart, hand: String) {
        for view in comboDetails.arrangedSubviews { comboDetails.removeArrangedSubview(view); view.removeFromSuperview() }
        let combos = chart.combinations(for: hand)
        if hand.hasSuffix("s") {
            for combo in combos {
                let view = FrequencyView()
                view.show(actions: chart.actions, frequencies: combo.frequencies, hand: combo.displayName, unavailable: combo.unavailableMessage)
                view.toolTip = combo.summary(actions: chart.actions)
                comboDetails.addArrangedSubview(view)
            }
        } else {
            for start in stride(from: 0, to: combos.count, by: 3) {
                let cells = combos[start..<min(start + 3, combos.count)].map { ComboCell(combo: $0, actions: chart.actions) }
                let gridRow = NSStackView(views: cells)
                gridRow.spacing = 6; gridRow.distribution = .fillEqually
                comboDetails.addArrangedSubview(gridRow)
                gridRow.widthAnchor.constraint(equalTo: comboDetails.widthAnchor).isActive = true
                for cell in cells { cell.heightAnchor.constraint(equalTo: cell.widthAnchor).isActive = true }
            }
        }
    }
    @objc func continueToFlop() {
        guard !busy, let handoff = pendingHandoff else { return }
        do { try beginSolve(handoff.input(flop: selectedFlop.joined(separator: ",")), handoff: handoff) }
        catch { setSource(String(describing: error)) }
    }
    @objc func startSolve() {
        guard !busy else { return }
        do {
            let input = try PostflopInput(board: selectedBoard.joined(separator: ","), pot: pot.stringValue, stack: stack.stringValue, ip: ip.stringValue, oop: oop.stringValue)
            try beginSolve(input)
        } catch { showError(error) }
    }
    func beginSolve(_ requestedInput: PostflopInput, handoff: PostflopHandoff? = nil, nextStreet: Bool = false, retryBudgetGiB: Double? = nil) throws {
        var input = requestedInput
        if let retryBudget = retryBudgetGiB {
            input.storageBudgetGiB = retryBudget
        } else {
            input.raiseLimit = raiseLimitPicker.indexOfSelectedItem
            input.betSizes = betSizeButtons.filter { $0.state == .on }.map { PostflopBetSize.allCases[$0.tag] }
            guard let budget = Double(storageBudget.stringValue), budget.isFinite, budget > 0, (budget * 1024).isFinite else {
                throw Failure("Enter a positive RAM budget in GiB.")
            }
            input.storageBudgetGiB = budget
        }
        guard !input.betSizes.isEmpty else { throw Failure("Select at least one bet size before solving.") }
        guard let home = defaultSolver() else { throw Failure("Bundled solver missing; rebuild Sui") }
        streetSolves.discardDifferentFlop(input)
        if let cached = streetSolves.matching(input) {
            postflop = try Postflop(input: input, output: cached.output)
            streetSolves.remember(input, output: cached.output, owned: cached.owned, preservingLater: streetSolves.entries[input.board.count]?.output == cached.output && streetSolves.entries[input.board.count]?.input.actionHistory == input.actionHistory)
            pendingHandoff = nil; flopSetup.isHidden = true; setup.isHidden = true
            renderPostflop(); return
        }
        storageBudget.stringValue = String(format: "%.4g", input.storageBudgetGiB)
        UserDefaults.standard.set(input.storageBudgetGiB, forKey: "solverStorageBudgetGiB")
        UserDefaults.standard.set(input.raiseLimit, forKey: "solverRaiseLimit")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("sui-solves/" + UUID().uuidString)
        betSizePicker.isHidden = true
        let control = SolverControl()
        solverControl = control
        stopNowButton.title = "Stop now"; stopNowButton.isEnabled = true; stopNowButton.isHidden = false
        resetButton.title = "Cancel"
        busy = true; mode.isEnabled = false; tableSize.isEnabled = false; stakesPicker.isEnabled = false; resetButton.isEnabled = true
        setup.isHidden = true; flopSetup.isHidden = true; clear()
        showHistory(input.actionHistory)
        sidebarScroll.isHidden = true; grid.alphaValue = 0.5
        grid.isPreview = true
        grid.chart = Chart(source: "", spot: Spot(id: "", position: input.oopSeat, actions: []), note: "", actions: [], frequencies: Dictionary(uniqueKeysWithValues: hands.map { ($0, [Double]()) }))
        progressTimer?.invalidate()
        var lastPreviewDate: Date?
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.status.stringValue = solverProgress(at: output)
            if let attributes = try? FileManager.default.attributesOfItem(atPath: output.appendingPathComponent("preview.json").path),
               let date = attributes[.modificationDate] as? Date, date != lastPreviewDate,
               let preview = try? Postflop(input: input, output: output, preview: true),
               let chart = try? preview.currentChart() {
                lastPreviewDate = date
                self.grid.chart = chart
            }
        }
        progressTimer = timer; RunLoop.main.add(timer, forMode: .common)
        // Written for Sui by us: keep the selected board visible during a solve.
        showBoard(input.board)
        status.stringValue = "Iteration 0 / 200"
        setSource("")
        source.toolTip = "Log: \(output.path)/solver.log"
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = Result { () throws -> Postflop in
                let solved = try solvePostflop(input, home: home, output: output, control: control, livePreview: true)
                if let handoff = handoff {
                    try json(handoff).write(to: output.appendingPathComponent("preflop.json"), atomically: true, encoding: .utf8)
                }
                return solved
            }
            DispatchQueue.main.async { [self] in
                betSizePicker.isHidden = false
                stopNowButton.isHidden = true
                historyWidthConstraint?.constant = -117
                resetButton.title = "Reset"
                busy = false; mode.isEnabled = true; tableSize.isEnabled = true; stakesPicker.isEnabled = true; resetButton.isEnabled = true
                progressTimer?.invalidate(); progressTimer = nil
                grid.alphaValue = 1; grid.isPreview = false; sidebarScroll.isHidden = false
                if resettingSolve {
                    resettingSolve = false
                    resetHand()
                    return
                }
                switch result {
                case .success(let solved):
                    streetSolves.remember(input, output: output, owned: true)
                    postflop = solved; pendingHandoff = nil; renderPostflop()
                case .failure(let error):
                    clear()
                    if nextStreet {
                        renderPostflop()
                        setSource("Could not calculate responses. Choose a card to retry.\n\n" + String(describing: error))
                    } else {
                        setup.isHidden = handoff != nil; flopSetup.isHidden = handoff == nil
                        status.stringValue = "Could not calculate responses"; showError(error)
                    }
                    if let limit = error as? SolverStorageLimit {
                        offerStorageRetry(limit, input: input, handoff: handoff, nextStreet: nextStreet)
                    }
                }
            }
        }
    }
    // Written for Sui by us: approval retries the same request in a fresh directory.
    func offerStorageRetry(_ limit: SolverStorageLimit, input: PostflopInput, handoff: PostflopHandoff?, nextStreet: Bool) {
        let amount = String(format: "%.0f", limit.suggestedBudgetGiB)
        let alert = NSAlert()
        alert.messageText = "Solver RAM budget exceeded"
        alert.informativeText = String(format: "This solve needs about %.2f GiB of RAM for its strategy arrays; the RAM budget is %.4g GiB. Raise the budget to %@ GiB and retry?\n\nIf this size is too large, consider reducing the number of bet sizes.", limit.requiredGiB, limit.budgetGiB, amount)
        alert.addButton(withTitle: "Raise to \(amount) GiB and Retry")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, !self.busy, response == .alertFirstButtonReturn else { return }
            do { try self.beginSolve(input, handoff: handoff, nextStreet: nextStreet, retryBudgetGiB: limit.suggestedBudgetGiB) }
            catch { self.setSource(String(describing: error)) }
        }
    }
    func chooseRange(_ field: NSTextField) {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { field.stringValue = url.path }
    }
    @objc func chooseIP() { chooseRange(ip) }
    @objc func chooseOOP() { chooseRange(oop) }
    func restoreSolveSettings(_ input: PostflopInput) {
        storageBudget.stringValue = String(format: "%.4g", input.storageBudgetGiB)
        raiseLimitPicker.selectItem(at: input.raiseLimit)
        for button in betSizeButtons { button.state = input.betSizes.contains(PostflopBetSize.allCases[button.tag]) ? .on : .off }
    }
    @objc func rewindStreet(_ sender: NSButton) { rewind(to: sender.tag) }
    func rewind(to street: Int) {
        guard !busy else { return }
        do {
            if street == 0 {
                guard preflop?.finished == true || streetSolves.entries[3] != nil else { return }
                if let entry = streetSolves.entries[3] { restoreSolveSettings(entry.input) }
                postflop = nil; showBoard([])
                if let preflop = preflop, preflop.finished {
                    renderPreflop()
                } else if let entry = streetSolves.entries[3] {
                    let input = entry.input
                    mode.selectItem(at: 1); pendingHandoff = nil; setup.isHidden = false; flopSetup.isHidden = true
                    selectedBoard = input.board; boardButton.title = input.board.map(cardDisplay).joined(separator: " ")
                    pot.stringValue = String(input.pot); stack.stringValue = String(input.stack)
                    ip.stringValue = input.ip.keys.sorted().map { "\($0):\(input.ip[$0]!)" }.joined(separator: ",")
                    oop.stringValue = input.oop.keys.sorted().map { "\($0):\(input.oop[$0]!)" }.joined(separator: ",")
                    clear(); betSizePicker.isHidden = false; status.stringValue = ""; showHistory(input.actionHistory)
                }
            } else if let entry = streetSolves.entries[street] {
                restoreSolveSettings(entry.input)
                postflop = try Postflop(input: entry.input, output: entry.output)
                pendingHandoff = nil; setup.isHidden = true; flopSetup.isHidden = true
                mode.selectItem(at: 1); renderPostflop()
            }
        } catch { showError(error) }
    }
    @objc func stopNow() {
        guard busy else { return }
        do {
            try solverControl.finish()
            stopNowButton.title = "Stopping…"; stopNowButton.isEnabled = false
        } catch { showError(error) }
    }
    func applicationWillTerminate(_ notification: Notification) { progressTimer?.invalidate(); solverControl.cancel() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
