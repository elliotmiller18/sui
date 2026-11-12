import Foundation

// Written for Sui by us: selectable sizes are shared by setup, labels and solver input.
enum PostflopBetSize: String, Codable, CaseIterable {
    case quarter, third, twoThirds, threeQuarters, oneAndHalf, triple, allin
    var percent: Double? {
        switch self {
        case .quarter: return 25
        case .third: return 100.0 / 3
        case .twoThirds: return 200.0 / 3
        case .threeQuarters: return 75
        case .oneAndHalf: return 150
        case .triple: return 300
        case .allin: return nil
        }
    }
    var title: String {
        switch self {
        case .quarter: return "1/4"
        case .third: return "1/3"
        case .twoThirds: return "2/3"
        case .threeQuarters: return "3/4"
        case .oneAndHalf: return "1.5x"
        case .triple: return "3x"
        case .allin: return "All-in"
        }
    }
}
let defaultPostflopBetSizes: [PostflopBetSize] = [.third, .oneAndHalf]
let postflopSizes = defaultPostflopBetSizes.map { (percent: $0.percent!, label: $0.title + " pot") }

let suits = Array("cdhs").map(String.init)
func cards(_ text: String) throws -> [String] {
    let result = text.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
    for card in result {
        let c = Array(card).map(String.init)
        guard c.count == 2, ranks.contains(c[0]), suits.contains(c[1]) else { throw Failure("Invalid card: \(card). Use cards such as As,Kd,2c.") }
    }
    guard Set(result).count == result.count else { throw Failure("Duplicate board card") }
    return result
}
func comboCards(_ combo: String) -> [String] { [String(combo.prefix(2)), String(combo.suffix(2))] }
func comboKey(_ combo: String) -> String { comboCards(combo).sorted().joined() }
func comboHand(_ combo: String) throws -> String {
    let c = Array(combo).map(String.init)
    guard c.count == 4 else { throw Failure("Invalid solver combo: \(combo)") }
    return try canonical(c[0] + c[2] + (c[0] == c[2] ? "" : (c[1] == c[3] ? "s" : "o")))[0]
}
func expandRange(_ range: [String: Double], board: [String]) throws -> [String: Double] {
    let deck = ranks.flatMap { rank in suits.map { rank + $0 } }.filter { !board.contains($0) }
    var result = [String: Double]()
    for i in 0..<deck.count {
        for j in (i+1)..<deck.count {
            let combo = deck[i] + deck[j]
            if let weight = try range[comboKey(combo)] ?? range[comboHand(combo)], weight > 0 { result[comboKey(combo)] = weight }
        }
    }
    return result
}
struct PostflopInput: Codable {
    var actionHistory = [HandHistoryAction]()
    var betSizes = defaultPostflopBetSizes
    var raiseLimit = 2
    var storageBudgetGiB = defaultSolverStorageBudgetGiB
    let board: [String]
    let pot: Double
    let stack: Double
    let ip: [String: Double]
    let oop: [String: Double]
    let ipSeat: String
    let oopSeat: String
    init(board: String, pot: String, stack: String, ip: String, oop: String, ipSeat: String = "IP", oopSeat: String = "OOP") throws {
        self.ipSeat = ipSeat; self.oopSeat = oopSeat
        self.board = try cards(board)
        guard (3...5).contains(self.board.count) else { throw Failure("Enter a flop, turn or river board (3–5 cards)") }
        guard let p = Double(pot), p.isFinite, p > 0, let s = Double(stack), s.isFinite, s > 0 else { throw Failure("Pot and effective stack must be positive BB amounts") }
        self.pot = p; self.stack = s
        func read(_ value: String) throws -> [String: Double] {
            let path = (value as NSString).expandingTildeInPath
            return try parseRange(FileManager.default.fileExists(atPath: path) ? String(contentsOfFile: path, encoding: .utf8) : value)
        }
        self.ip = try read(ip); self.oop = try read(oop)
        let a = try expandRange(self.ip, board: self.board), b = try expandRange(self.oop, board: self.board)
        guard a.keys.contains(where: { ac in b.keys.contains { Set(comboCards(ac)).isDisjoint(with: comboCards($0)) } }) else { throw Failure("Ranges have no compatible hands on this board") }
    }
    init(board: [String], pot: Double, stack: Double, ip: [String: Double], oop: [String: Double], seats: [String]) {
        self.board = board; self.pot = pot; self.stack = stack
        self.ip = ip; self.oop = oop; self.ipSeat = seats[0]; self.oopSeat = seats[1]
    }
    func script() -> String {
        func rangeText(_ value: [String: Double]) -> String {
            value.keys.sorted().filter { value[$0]! > 0 }.map { "\($0):\(value[$0]!)" }.joined(separator: ",")
        }
        var lines = ["set_pot \(pot)", "set_effective_stack \(stack)", "set_board \(board.joined(separator: ","))", "set_range_ip \(rangeText(ip))", "set_range_oop \(rangeText(oop))"]
        for player in ["ip", "oop"] {
            for street in ["flop", "turn", "river"] {
                let sizes = betSizes.compactMap { $0.percent }.map { String(format: "%.8g", $0) }.joined(separator: ",")
                if !sizes.isEmpty {
                    for action in ["bet", "raise", "donk"] { lines.append("set_bet_sizes \(player),\(street),\(action),\(sizes)") }
                }
                if betSizes.contains(.allin) { lines.append("set_bet_sizes \(player),\(street),allin") }
            }
        }
        // Solve future play, but export only this street. Re-solve after a card is chosen.
        // Written for Sui by us: use a 2% exploitability target for interactive solves.
        // Written for Sui by us: upstream counts the opening bet as 1.
        lines += ["set_allin_threshold 1", "set_raise_limit \(raiseLimit + 1)", "build_tree", "set_thread_num \(min(4, ProcessInfo.processInfo.activeProcessorCount))", "set_accuracy 2", "set_max_iteration 200", "set_print_interval 10", "set_use_isomorphism 0", "start_solve", "set_dump_rounds 1", "dump_result result.json"]
        return lines.joined(separator: "\n") + "\n"
    }
}
struct SolverStrategy: Decodable { let actions: [String]; let strategy: [String: [Double]] }
struct SolverNode: Decodable {
    let node_type: String
    let player: Int?
    let actions: [String]?
    let strategy: SolverStrategy?
    let childrens: [String: SolverNode]?
    let dealcards: [String: SolverNode]?
}
final class Postflop {
    private(set) var node: SolverNode
    private(set) var board: [String]
    private(set) var pot: Double
    private(set) var remaining: [Double]
    private var committed = [0.0, 0.0]
    private var reach: [[String: Double]]
    private(set) var ending: String?
    private(set) var actionHistory: [HandHistoryAction]
    let resultPath: String
    let convergence: String
    let seats: [String]
    let betSizes: [PostflopBetSize]
    let raiseLimit: Int
    let storageBudgetGiB: Double
    var actor: String { seats[node.player == 0 ? 0 : 1] }
    var needsCard: Bool { ending == nil && remaining.allSatisfy { $0 > 0.001 } && board.count < 5 && node.node_type == "chance_node" }
    var actions: [String] { ending == nil ? (node.actions ?? []) : [] }
    var nextCards: [String] {
        guard needsCard, board.count < 5 else { return [] }
        return ranks.flatMap { rank in suits.map { rank + $0 } }.filter { card in
            guard !board.contains(card) else { return false }
            let ip = reach[0].filter { $0.value > 0 && !comboCards($0.key).contains(card) }
            let oop = reach[1].filter { $0.value > 0 && !comboCards($0.key).contains(card) }
            return ip.keys.contains { a in oop.keys.contains { Set(comboCards(a)).isDisjoint(with: comboCards($0)) } }
        }.sorted()
    }
    init(input: PostflopInput, output: URL, preview: Bool = false) throws {
        self.actionHistory = input.actionHistory
        self.raiseLimit = input.raiseLimit
        self.storageBudgetGiB = input.storageBudgetGiB
        self.betSizes = input.betSizes
        self.seats = [input.ipSeat, input.oopSeat]
        self.node = try JSONDecoder().decode(SolverNode.self, from: Data(contentsOf: output.appendingPathComponent(preview ? "preview.json" : "result.json")))
        guard node.node_type == "action_node", node.strategy != nil else { throw Failure("Result does not contain a decision strategy") }
        self.board = input.board; self.pot = input.pot; self.remaining = [input.stack, input.stack]
        self.reach = try [expandRange(input.ip, board: input.board), expandRange(input.oop, board: input.board)]
        self.resultPath = output.path
        let log = preview ? "" : ((try? String(contentsOf: output.appendingPathComponent("solver.log"), encoding: .utf8)) ?? "")
        convergence = log.components(separatedBy: .newlines).last { $0.hasPrefix("Total exploitability ") }.map { $0.replacingOccurrences(of: "precent", with: "%") } ?? "Convergence unavailable; inspect solver.log."
    }
    // v0.2.0 exports BET and RAISE amounts as additional chips, not raise-to totals.
    func label(_ action: String) -> String {
        let parts = action.split(separator: " ")
        guard parts.count == 2, let amount = Double(parts[1]), let player = node.player else { return action.capitalized }
        let allin = abs(amount - remaining[player]) < 0.001
        // Written for Sui by us: exported raises include the call, then the
        // chosen fraction of the pot after calling. Keep all-in independent of size.
        let toCall = max(0, committed[1-player] - committed[player])
        let isRaise = parts[0] == "RAISE"
        let ratio = (amount - (isRaise ? toCall : 0)) / (pot + (isRaise ? toCall : 0)) * 100
        let size = PostflopBetSize.allCases.filter { $0.percent != nil }.min { abs($0.percent! - ratio) < abs($1.percent! - ratio) }
        let fraction = size.flatMap { abs($0.percent! - ratio) < 0.01 ? $0.title + " pot" : nil } ?? String(format: "%.1f%% pot", ratio)
        let name = allin ? "All-in" : "\(isRaise ? "Raise" : "Bet") \(fraction)"
        return "\(name) · \(String(format: "%.4g", amount)) BB"
    }
    func currentChart() throws -> Chart? {
        guard ending == nil, !needsCard else { return nil }
        guard let strategy = node.strategy, let player = node.player, (0...1).contains(player), strategy.actions == node.actions else { throw Failure("Incomplete solver decision") }
        let count = strategy.actions.count
        var totals = [String: Double](), vectors = [String: [Double]]()
        var comboVectors = [String: [Double]]()
        for (combo, vector) in strategy.strategy {
            guard vector.count == count, vector.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1.00001 }), abs(vector.reduce(0,+) - 1) < 0.001 else { throw Failure("Invalid solver frequencies") }
            let key = comboKey(combo), weight = reach[player][key] ?? 0
            guard weight > 0, !comboCards(combo).contains(where: { board.contains($0) }) else { continue }
            comboVectors[key] = vector
            let hand = try comboHand(combo)
            totals[hand, default: 0] += weight
            var values = vectors[hand] ?? Array(repeating: 0, count: count)
            for i in 0..<count { values[i] += vector[i] * weight }
            vectors[hand] = values
        }
        for hand in hands {
            if let total = totals[hand], total > 0 { vectors[hand] = vectors[hand]!.map { $0 / total } }
            else { vectors[hand] = Array(repeating: 0, count: count) }
        }
        return Chart(source: "TexasSolver · \(actor) to act", spot: Spot(id: board.joined(separator: " "), position: actor, actions: []), note: "Reach-weighted suit average. Gray hands are outside the current range.\n\(convergence)", actions: actions.map(label), frequencies: vectors, comboWeights: totals, comboFrequencies: comboVectors, comboReach: reach[player], board: board)
    }
    func advance(_ action: String) throws {
        guard let strategy = node.strategy, let index = actions.firstIndex(of: action), let player = node.player else { throw Failure("Action is unavailable") }
        let next = node.childrens?[action]
        let calledAllIn = action == "CALL" && remaining[player] - (committed[1-player] - committed[player]) <= 0.001
        let terminal = action == "FOLD" || calledAllIn || ((action == "CALL" || action == "CHECK") && board.count == 5 && next == nil)
        guard next != nil || terminal else { throw Failure("Missing continuation in solver output") }
        var conditioned = [String: Double]()
        for (combo, vector) in strategy.strategy {
            guard vector.indices.contains(index) else { throw Failure("Invalid solver strategy") }
            let key = comboKey(combo)
            conditioned[key] = (reach[player][key] ?? 0) * vector[index]
        }
        let parts = action.split(separator: " ")
        let payment: Double
        if action == "CALL" { payment = committed[1-player] - committed[player] }
        else if parts.count == 2, let amount = Double(parts[1]) { payment = amount }
        else { payment = 0 }
        guard payment >= -0.001, payment <= remaining[player] + 0.001 else { throw Failure("Unsupported solver amount format (expected TexasSolver v0.2.0)") }
        let street = board.count == 3 ? "Flop" : (board.count == 4 ? "Turn" : "River")
        actionHistory.append(HandHistoryAction(street: street, board: board, seat: seats[player], action: label(action), amountBB: payment > 0 ? payment : nil))
        reach[player] = conditioned
        committed[player] += payment; remaining[player] -= payment; pot += payment
        if action == "FOLD" { ending = "Hand ended — \(seats[1-player]) wins." }
        else if calledAllIn { ending = "All-in called — no further decisions." }
        else if terminal { ending = "Hand ended — showdown." }
        if let next = next { node = next }
    }
    func nextStreetInput(_ card: String) throws -> PostflopInput {
        guard needsCard, nextCards.contains(card), remaining.min()! > 0 else { throw Failure("Card unavailable for these ranges") }
        func conditioned(_ range: [String: Double]) -> [String: Double] {
            let filtered = range.filter { $0.value > 0 && !comboCards($0.key).contains(card) }
            let maximum = filtered.values.max()!
            return filtered.mapValues { $0 / maximum }
        }
        var input = PostflopInput(board: board + [card], pot: pot, stack: remaining.min()!,
                             ip: conditioned(reach[0]), oop: conditioned(reach[1]), seats: seats)
        input.actionHistory = actionHistory
        input.betSizes = betSizes
        input.raiseLimit = raiseLimit
        input.storageBudgetGiB = storageBudgetGiB
        return input
    }
}

func solvePostflop(_ input: PostflopInput, home: URL, output: URL, timeout: Double? = nil, control: SolverControl? = nil, livePreview: Bool = false) throws -> Postflop {
    guard (0...2).contains(input.raiseLimit) else { throw Failure("Raise limit must be between 0 and 2 per street") }
    let request = FileManager.default.temporaryDirectory.appendingPathComponent("sui-request-" + UUID().uuidString + ".txt")
    try input.script().write(to: request, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: request) }
    let outputExisted = FileManager.default.fileExists(atPath: output.path)
    do { try runSolver(home: home, input: request, output: output, seconds: timeout, control: control, announce: false, storageBudgetGiB: input.storageBudgetGiB, livePreview: livePreview) }
    catch {
        // Written for Sui by us: preserve failed requests without overwriting a
        // previous solve if the caller mistakenly supplied an existing folder.
        if !outputExisted {
            try? json(input).write(to: output.appendingPathComponent("setup.json"), atomically: true, encoding: .utf8)
        }
        throw error
    }
    try json(input).write(to: output.appendingPathComponent("setup.json"), atomically: true, encoding: .utf8)
    return try Postflop(input: input, output: output)
}

// Keep completed street exports while navigating. Never delete an imported solve.
final class StreetSolveHistory {
    struct Entry { let input: PostflopInput; let output: URL; let owned: Bool }
    private(set) var entries = [Int: Entry]()
    private var retained = [String: Entry]()
    func matching(_ input: PostflopInput) -> Entry? {
        guard let entry = retained[input.script()],
              FileManager.default.fileExists(atPath: entry.output.appendingPathComponent("result.json").path) else { return nil }
        return entry
    }
    func discardDifferentFlop(_ input: PostflopInput) {
        guard input.board.count == 3, let old = entries.values.first,
              Set(old.input.board.prefix(3)) != Set(input.board) else { return }
        // Keep alternate action/runout branches until the user chooses a new flop.
        for entry in retained.values where entry.owned { try? FileManager.default.removeItem(at: entry.output) }
        entries.removeAll(); retained.removeAll()
    }
    func remember(_ input: PostflopInput, output: URL, owned: Bool, preservingLater: Bool = false) {
        if !preservingLater {
            for key in Array(entries.keys) where key > input.board.count { entries.removeValue(forKey: key) }
        }
        let entry = Entry(input: input, output: output, owned: owned)
        entries[input.board.count] = entry; retained[input.script()] = entry
    }
    func reset() { entries.removeAll(); retained.removeAll() }
}
