import AppKit

func color(_ label: String) -> NSColor {
    let text = label.lowercased()
    if text.contains("unassigned") { return NSColor(calibratedWhite: 0.20, alpha: 1) }
    if text.contains("fold") { return NSColor(calibratedRed: 0.27, green: 0.40, blue: 0.58, alpha: 1) }
    if text.contains("call") || text.contains("check") { return NSColor(calibratedRed: 0.18, green: 0.58, blue: 0.46, alpha: 1) }
    if text.contains("all-in") { return NSColor(calibratedRed: 0.65, green: 0.23, blue: 0.45, alpha: 1) }
    return NSColor(calibratedRed: 0.85, green: 0.39, blue: 0.29, alpha: 1)
}
final class Grid: NSView {
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
            if hand == selected {
                NSColor.white.setStroke(); let path = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1)); path.lineWidth = 2; path.stroke()
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let row = Int(p.y / (bounds.height / 13)), col = Int(p.x / (bounds.width / 13))
        guard (0..<13).contains(row), (0..<13).contains(col) else { return }
        selected = hands[row * 13 + col]; onSelect?(selected)
    }
}
final class Desktop: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var root: URL
    let initial: Spot?
    let remainder: String
    let raiseBB: String?
    var preflop: Preflop?
    var postflop: Postflop?
    var pendingHandoff: PostflopHandoff?
    let flopSetup = NSStackView()
    var selectedFlop = [String]()
    let solverControl = SolverControl()
    var busy = false
    let grid = Grid()
    let spinner = NSProgressIndicator()
    let loading = NSStackView()
    let elapsedLabel = NSTextField(labelWithString: "")
    let progressLabel = NSTextField(labelWithString: "")
    var progressTimer: Timer?
    let mode = NSPopUpButton()
    let status = NSTextField(labelWithString: "")
    // Written for Sui by us: show board cards using the selector's card tiles.
    let boardCards = NSStackView()
    let folder = NSTextField(labelWithString: "")
    let detail = NSTextField(wrappingLabelWithString: "")
    let source = NSTextField(wrappingLabelWithString: "")
    let legend = NSStackView()
    let setup = NSStackView()
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
        let toolbar = row([mode])
        folder.font = .systemFont(ofSize: 11); folder.textColor = .secondaryLabelColor; folder.lineBreakMode = .byTruncatingMiddle
        folder.stringValue = "100 BB · 6-max · 2.5 BB opening ranges"; folder.toolTip = root.path
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
        let header = NSStackView(views: [toolbar, folder, setup, statusRow, flopSetup]); header.orientation = .vertical; header.alignment = .leading; header.spacing = 12
        legend.orientation = .vertical; legend.alignment = .leading; legend.spacing = 10
        detail.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        source.font = .systemFont(ofSize: 11); source.textColor = .secondaryLabelColor
        let sidebar = NSStackView(views: [label("ACTIONS", size: 11, bold: true), legend, label("SELECTED HAND", size: 11, bold: true), detail, source])
        sidebar.orientation = .vertical; sidebar.alignment = .leading; sidebar.spacing = 16
        for v in [header, grid, sidebar] { v.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(v) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 20), header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24), header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 20), grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24), grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            sidebar.topAnchor.constraint(equalTo: grid.topAnchor), sidebar.leadingAnchor.constraint(equalTo: grid.trailingAnchor, constant: 24), sidebar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24), sidebar.widthAnchor.constraint(equalToConstant: 260), sidebar.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24)
        ])
        spinner.style = .spinning; spinner.isIndeterminate = true
        spinner.controlSize = .regular
        loading.orientation = .vertical; loading.spacing = 16; loading.alignment = .centerX
        loading.addArrangedSubview(spinner)
        loading.addArrangedSubview(label("Calculating responses…", size: 15))
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        progressLabel.font = .systemFont(ofSize: 12); progressLabel.textColor = .secondaryLabelColor
        progressLabel.alignment = .center; progressLabel.maximumNumberOfLines = 3
        loading.addArrangedSubview(elapsedLabel); loading.addArrangedSubview(progressLabel)
        loading.translatesAutoresizingMaskIntoConstraints = false; grid.addSubview(loading)
        NSLayoutConstraint.activate([
            loading.centerXAnchor.constraint(equalTo: grid.centerXAnchor),
            loading.centerYAnchor.constraint(equalTo: grid.centerYAnchor)
        ])
        loading.isHidden = true
        grid.onSelect = { [weak self] _ in self?.updateDetail() }
        if postflop != nil { mode.selectItem(at: 1); setup.isHidden = true; renderPostflop() }
        else if let initial = initial {
            setup.isHidden = true
            do { show(try chart(initial, remainder: remainder, raiseBB: raiseBB), clickable: false); status.stringValue = "\(initial.position) · Chart preview" }
            catch { showError(error) }
        } else { changeMode() }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    // Written for Sui by us: reuse the exact tile size, suit colors and drawing from the picker.
    func showBoard(_ cards: [String]) {
        for view in boardCards.arrangedSubviews { boardCards.removeArrangedSubview(view); view.removeFromSuperview() }
        for card in cards {
            let tile = CardButton()
            tile.title = cardDisplay(card); tile.displayOnly = true; tile.isBordered = false
            tile.suitColor = ["s": NSColor.white, "h": .systemRed, "c": .systemGreen, "d": .systemBlue][String(card.suffix(1))] ?? .white
            tile.widthAnchor.constraint(equalToConstant: 40).isActive = true
            tile.heightAnchor.constraint(equalToConstant: 42).isActive = true
            boardCards.addArrangedSubview(tile)
        }
        boardCards.isHidden = cards.isEmpty
    }
    func clear() {
        grid.chart = nil; detail.stringValue = ""; source.stringValue = ""; actionKeys = []
        for view in legend.arrangedSubviews { legend.removeArrangedSubview(view); view.removeFromSuperview() }
    }
    func show(_ chart: Chart, clickable: Bool = true) {
        clear(); grid.chart = chart
        for (index, action) in chart.actions.enumerated() {
            let dot = label("■", size: 18); dot.textColor = color(action)
            let button = NSButton(title: action, target: self, action: #selector(selectAction(_:)))
            button.tag = index; button.isEnabled = clickable; button.bezelStyle = .rounded
            legend.addArrangedSubview(row([dot, button]))
        }
        source.stringValue = clickable ? "Click an action to continue." : chart.source + "\n\n" + chart.note
        source.toolTip = chart.source + "\n\n" + chart.note
        updateDetail()
    }
    func showError(_ error: Error) { clear(); source.stringValue = String(describing: error) }
    @objc func changeMode() {
        guard !busy else { return }
        // Written for Sui by us: clear the previous board when starting a new flow.
        showBoard([])
        postflop = nil; preflop = nil; pendingHandoff = nil; flopSetup.isHidden = true; clear()
        setup.isHidden = mode.indexOfSelectedItem == 0
        if mode.indexOfSelectedItem == 0 {
            do { preflop = try Preflop(root: root); renderPreflop() }
            catch { status.stringValue = "Preflop"; showError(error) }
        } else { status.stringValue = "Postflop · Heads-up"; source.stringValue = "Enter both ranges and a board. Pot-sized bets/raises and all-in. No rake." }
    }
    func renderPreflop() {
        guard let preflop = preflop else { return }
        status.stringValue = preflop.message
        do {
            if let current = try preflop.currentChart() { show(current); actionKeys = current.actions }
            else {
                clear()
                if preflop.ending != nil { pendingHandoff = nil; flopSetup.isHidden = true; return }
                let handoff = try preflop.handoff()
                pendingHandoff = handoff
                mode.selectItem(at: 1); setup.isHidden = true; flopSetup.isHidden = false
                selectedFlop = []
                status.stringValue = "Postflop · \(handoff.oopSeat) vs \(handoff.ipSeat) · Pot \(String(format: "%.2f", handoff.pot)) BB · Stack \(String(format: "%.2f", handoff.stack)) BB"
                source.stringValue = "Choose the flop to continue this hand.\n\nPot, stacks and both ranges are carried forward. Postflop uses no rake."
            }
        } catch { showError(error) }
    }
    func renderPostflop() {
        guard let postflop = postflop else { return }
        // Written for Sui by us: board ranks/suits are rendered as tiles, not plain text.
        showBoard(postflop.board)
        status.stringValue = "Pot \(String(format: "%.2f", postflop.pot)) BB · \(postflop.actor)"
        do {
            if let ending = postflop.ending { clear(); status.stringValue = ending; return }
            if postflop.needsCard {
                guard !postflop.nextCards.isEmpty else {
                    clear(); status.stringValue = "No hands reach this line"
                    source.stringValue = "The selected actions have zero frequency for every remaining hand."
                    return
                }
                clear()
                legend.addArrangedSubview(NSButton(title: postflop.board.count == 3 ? "Choose turn…" : "Choose river…", target: self, action: #selector(dealCard)))
                source.stringValue = "Choose the next board card to continue."
            } else if let current = try postflop.currentChart() { show(current); actionKeys = postflop.actions; source.stringValue = "Click an action to continue.\n\n" + postflop.convergence; source.toolTip = current.source + "\n" + current.note + "\n" + postflop.resultPath }
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
            catch { self.showError(error) }
        }
    }
    func updateDetail() {
        guard let current = grid.chart, let values = current.frequencies[grid.selected] else { return }
        if values.reduce(0,+) == 0 { detail.stringValue = "\(grid.selected)\nOutside current range"; return }
        detail.stringValue = grid.selected + "\n\n" + zip(current.actions, values).map { "\($0.0)\n\(String(format: "%.1f%%", $0.1 * 100))" }.joined(separator: "\n\n")
    }
    @objc func continueToFlop() {
        guard !busy, let handoff = pendingHandoff else { return }
        do { try beginSolve(handoff.input(flop: selectedFlop.joined(separator: ",")), handoff: handoff) }
        catch { source.stringValue = String(describing: error) }
    }
    @objc func startSolve() {
        guard !busy else { return }
        do {
            let input = try PostflopInput(board: selectedBoard.joined(separator: ","), pot: pot.stringValue, stack: stack.stringValue, ip: ip.stringValue, oop: oop.stringValue)
            try beginSolve(input)
        } catch { showError(error) }
    }
    func beginSolve(_ input: PostflopInput, handoff: PostflopHandoff? = nil, nextStreet: Bool = false) throws {
        guard let home = defaultSolver() else { throw Failure("Bundled solver missing; rebuild Sui") }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("sui-solves/" + UUID().uuidString)
        busy = true; mode.isEnabled = false; setup.isHidden = true; flopSetup.isHidden = true; clear()
        loading.isHidden = false; spinner.startAnimation(nil)
        let started = ProcessInfo.processInfo.systemUptime
        elapsedLabel.stringValue = "Elapsed 0:00"; progressLabel.stringValue = "Preparing solver…"
        progressTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let seconds = Int(ProcessInfo.processInfo.systemUptime - started)
            self.elapsedLabel.stringValue = String(format: "Elapsed %d:%02d", seconds / 60, seconds % 60)
            self.progressLabel.stringValue = solverProgress(at: output)
        }
        progressTimer = timer; RunLoop.main.add(timer, forMode: .common)
        // Written for Sui by us: keep the selected board visible during a solve.
        showBoard(input.board)
        status.stringValue = "Calculating responses…"
        source.stringValue = "Preparing the next decision. This can take several minutes."
        source.toolTip = "Log: \(output.path)/solver.log"
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = Result { () throws -> Postflop in
                let solved = try solvePostflop(input, home: home, output: output, control: solverControl)
                if let handoff = handoff {
                    try json(handoff).write(to: output.appendingPathComponent("preflop.json"), atomically: true, encoding: .utf8)
                }
                return solved
            }
            DispatchQueue.main.async { [self] in
                busy = false; mode.isEnabled = true
                progressTimer?.invalidate(); progressTimer = nil
                spinner.stopAnimation(nil); loading.isHidden = true
                switch result {
                case .success(let solved): postflop = solved; pendingHandoff = nil; renderPostflop()
                case .failure(let error):
                    if nextStreet {
                        renderPostflop()
                        source.stringValue = "Could not calculate responses. Choose a card to retry.\n\n" + String(describing: error)
                    } else {
                        setup.isHidden = handoff != nil; flopSetup.isHidden = handoff == nil
                        status.stringValue = "Could not calculate responses"; showError(error)
                    }
                }
            }
        }
    }
    func chooseRange(_ field: NSTextField) {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { field.stringValue = url.path }
    }
    @objc func chooseIP() { chooseRange(ip) }
    @objc func chooseOOP() { chooseRange(oop) }
    func applicationWillTerminate(_ notification: Notification) { progressTimer?.invalidate(); solverControl.cancel() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
