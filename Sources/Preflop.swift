import Foundation

// The flat 100bb library omits folds by players who have not yet invested.
// Preserve folds after an earlier action so distinct response lines never merge.
func historyKey(_ tokens: [String]) -> String {
    var invested = Set<String>(), result = [String]()
    for i in stride(from: 0, to: tokens.count - 1, by: 2) {
        let player = position(tokens[i]), action = tokens[i+1].lowercased()
        if action != "fold" || invested.contains(player) { result += [player, action] }
        if action != "fold" { invested.insert(player) }
    }
    return result.joined(separator: "_")
}
struct PreflopAction {
    let token: String
    let file: ActionFile
    // Written for Sui by us: JSON charts carry absolute action reach separately from their display frequencies.
    var range: [String: Double]? = nil
}
struct PostflopHandoff: Codable {
    let oopSeat: String
    let ipSeat: String
    let pot: Double
    let stack: Double
    let oopRange: [String: Double]
    let ipRange: [String: Double]
    let history: [String]
    let rangeSources: [String: String]

    func input(flop: String) throws -> PostflopInput {
        guard try cards(flop).count == 3 else { throw Failure("Enter exactly three flop cards, e.g. Qs,8d,7h") }
        func text(_ range: [String: Double]) -> String {
            range.keys.sorted().map { "\($0):\(range[$0]!)" }.joined(separator: ",")
        }
        return try PostflopInput(board: flop, pot: String(pot), stack: String(stack), ip: text(ipRange), oop: text(oopRange), ipSeat: ipSeat, oopSeat: oopSeat)
    }
}
final class Preflop {
    // Written for Sui by us: remove early seats for smaller tables, keeping the blinds intact.
    static func seats(for players: Int) -> [String] {
        if players == 2 { return ["SB", "BB"] }
        let ring = ["UTG", "UTG+1", "UTG+2", "LJ", "HJ", "CO", "BTN", "SB", "BB"]
        if players == 6 { return ["UTG", "HJ", "CO", "BTN", "SB", "BB"] }
        if players == 7 { return ["UTG", "LJ", "HJ", "CO", "BTN", "SB", "BB"] }
        if players == 8 { return ["UTG", "UTG+1", "LJ", "HJ", "CO", "BTN", "SB", "BB"] }
        return Array(ring.suffix(players))
    }
    let seats: [String]
    let players: Int
    let stakes: String
    let root: URL
    private var cash: [String: [String: Double]]?
    private var headsUp: HeadsUpCharts?
    private var raises = 0
    private var aggressor: Int?
    private var continuationRanges = [Int: [String: Double]]()
    private var rangeSources = [String: String]()
    private var index: [String: [PreflopAction]] = [:]
    private(set) var history = [String]()
    private(set) var queue: [Int]
    private(set) var folded = Set<Int>()
    private(set) var allin = Set<Int>()
    private(set) var committed: [Double]
    var actor: String? { queue.first.map { seats[$0] } }
    var finished: Bool { queue.isEmpty || folded.count == players - 1 }
    var pot: Double { committed.reduce(0,+) }
    var ending: String? {
        if folded.count == players - 1 { return "Hand ended — \(seats[(0..<players).first { !folded.contains($0) }!]) wins." }
        if finished && (0..<players).filter({ !folded.contains($0) }).allSatisfy({ committed[$0] >= 100 - 0.001 }) {
            return "All-in called — no further decisions."
        }
        return nil
    }
    var message: String {
        if let ending = ending { return ending }
        if finished { return "Postflop" }
        return "\(actor!) to act · Pot \(String(format: "%.1f", pot)) BB"
    }
    init(root: URL, players: Int = 6, stakes: String = "NL500") throws {
        guard (2...9).contains(players), ["NL50", "NL500"].contains(stakes) else { throw Failure("Choose 2–9 players and NL50 or NL500") }
        self.root = root; self.players = players; self.stakes = stakes
        seats = Self.seats(for: players); queue = Array(0..<players)
        committed = Array(repeating: 0, count: players); committed[players - 2] = 0.5; committed[players - 1] = 1
        if stakes == "NL50" {
            if players == 2 {
                headsUp = try JSONDecoder().decode(HeadsUpCharts.self, from: Data(contentsOf: root.appendingPathComponent("heads-up.json")))
            } else {
                cash = try JSONDecoder().decode([String: [String: Double]].self, from: Data(contentsOf: root.appendingPathComponent("nl50-cash.json")))
            }
            return
        }
        guard players == 6 else { throw Failure("NL500 charts are currently available only for 6 players. Select NL50 for this table size.") }
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { throw Failure("Cannot read range library") }
        for case let file as URL in walker where file.pathExtension == "txt" {
            let tokens = file.deletingPathExtension().lastPathComponent.components(separatedBy: "_")
            guard tokens.count >= 2, tokens.count % 2 == 0,
                  seats.contains(position(tokens[tokens.count-2])),
                  let label = actionLabel(tokens.last!) else { continue }
            let key = historyKey(Array(tokens.dropLast(2))) + "|" + position(tokens[tokens.count-2])
            let item = PreflopAction(token: tokens.last!, file: ActionFile(label: label, path: file.path))
            if index[key, default: []].contains(where: { $0.token.lowercased() == item.token.lowercased() }) {
                throw Failure("Ambiguous range library: duplicate decision \(key). Choose the 100bb 2.5x 500rake folder itself.")
            }
            index[key, default: []].append(item)
        }
        guard index["|UTG"] != nil else { throw Failure("Click-through requires the bundled ‘100bb 2.5x 500rake’ library (UTG action filenames).") }
    }
    func options() -> [PreflopAction] {
        guard let actor = actor, !finished else { return [] }
        if cash != nil || headsUp != nil { return (try? importedDecision().actions) ?? [] }
        return (index[historyKey(history) + "|" + actor] ?? []).sorted { $0.file.label < $1.file.label }
    }
    func currentChart() throws -> Chart? {
        if finished { return nil }
        if cash != nil || headsUp != nil { return try importedDecision().chart }
        let options = options()
        guard !options.isEmpty else { throw Failure("No stored response for \(actor!) after this line. This library does not cover every branch.") }
        // Written for Sui by us: these files are cumulative reach weights. Condition
        // the grid on the player's earlier action rather than showing unreachable hands as folds.
        let weighted = try options.map { action -> PreflopAction in
            var action = action
            action.range = try parseRange(String(contentsOfFile: action.file.path, encoding: .utf8))
            return action
        }
        return try decision(weighted, source: "TexasSolver bundled 100bb 2.5x 500rake", note: "Original pack; detailed solver/rake metadata unavailable.", rounding: 0.002).chart
    }
    func handoff() throws -> PostflopHandoff {
        guard finished else { throw Failure("Preflop betting is not complete") }
        // Postflop order starts at SB, then BB, then UTG through BTN.
        let order = players == 2 ? [1, 0] : [players - 2, players - 1] + Array(0..<(players - 2))
        let live = order.filter { !folded.contains($0) }
        guard live.count == 2 else { throw Failure("Postflop solving supports two players; \(live.count) remain.") }
        let effective = live.map { 100 - committed[$0] }.min()!
        guard effective > 0 else { throw Failure("All-in called — no further betting decisions.") }
        guard let oop = continuationRanges[live[0]], let ip = continuationRanges[live[1]],
              oop.values.contains(where: { $0 > 0 }), ip.values.contains(where: { $0 > 0 }) else { throw Failure("No continuation range for a remaining player") }
        return PostflopHandoff(oopSeat: seats[live[0]], ipSeat: seats[live[1]], pot: pot, stack: effective,
                              oopRange: oop, ipRange: ip, history: history, rangeSources: rangeSources.filter { [seats[live[0]], seats[live[1]]].contains($0.key) })
    }
    func advance(_ label: String) throws {
        guard let seat = queue.first, !finished else { throw Failure("Preflop has ended") }
        let available = cash != nil || headsUp != nil ? try importedDecision().actions : options()
        let selected = available.first { $0.file.label == label }
        guard selected != nil || (label == "Fold" && cash == nil && headsUp == nil) else { throw Failure("Action has no stored range") }
        let token = selected?.token ?? "FOLD"
        // These files describe the player's range after the named line. Keep the
        // latest range as-is; multiplying earlier chart weights would count reach twice.
        let selectedRange: [String: Double]?
        if token.lowercased() != "fold", let selected = selected {
            selectedRange = try selected.range ?? parseRange(String(contentsOfFile: selected.file.path, encoding: .utf8))
            guard selectedRange!.values.contains(where: { $0 > 0 }) else { throw Failure("No hands take this action on the selected line") }
        } else { selectedRange = nil }
        let oldBet = committed.max()!
        queue.removeFirst()
        if token.lowercased() == "fold" { folded.insert(seat) }
        else if token.lowercased() == "call" {
            guard committed[seat] < oldBet else { throw Failure("Nothing to call") }
            committed[seat] = oldBet
        } else if token.lowercased() == "check" {
            guard committed[seat] == oldBet else { throw Failure("Cannot check facing a raise") }
        } else if token.lowercased() == "allin" { committed[seat] = 100; allin.insert(seat) }
        else if token.lowercased().hasSuffix("bb"), let amount = Double(token.dropLast(2)), amount > oldBet { committed[seat] = amount }
        else { throw Failure("Unsupported preflop action: \(token)") }
        if let selectedRange = selectedRange {
            continuationRanges[seat] = selectedRange
            rangeSources[seats[seat]] = selected!.file.path
        }
        if committed[seat] >= 100 - 0.001 { allin.insert(seat) }
        history += [seats[seat], token]
        // Once two players enter voluntarily, all other seats auto-fold.
        // Blinds remain in the pot, but do not count as entering the hand.
        let entered = Set(continuationRanges.keys).subtracting(folded)
        if entered.count == 2 {
            for other in 0..<players where !entered.contains(other) && !folded.contains(other) {
                folded.insert(other)
                history += [seats[other], "FOLD"]
            }
            queue.removeAll { folded.contains($0) || allin.contains($0) }
        }
        if committed[seat] > oldBet {
            raises += 1; aggressor = seat
            queue = (1..<players).map { (seat + $0) % players }.filter { !folded.contains($0) && !allin.contains($0) }
        }
        if folded.count == players - 1 { queue = [] }
        // Written for Sui by us: a blind with no call to pay still gets its option
        // after a limp. The pending-action queue closes betting after that check.
    }

    // Written for Sui by us: preserve source mixes, sizes and absolute reach for
    // the postflop bridge. Missing charts fail instead of substituting another spot.
    private struct HeadsUpCharts: Decodable { let spots: [HeadsUpSpot] }
    private struct HeadsUpSpot: Decodable {
        let key: String
        let aLabel: String?
        let bLabel: String
        let sizeTo: Double?
        let canFold: Bool
        let a: [Double]
        let b: [Double]
    }
    var libraryNote: String {
        if stakes == "NL500" { return "100 BB · 6 players · NL500 pack (rake metadata unverified)" }
        if players == 2 { return "100 BB · Heads-up · SolvePoker · 5% rake, 2 BB cap" }
        return "100 BB · NL50-style · Poker Trainer · \(players) players" + (players == 9 ? "" : " · Earlier seats omitted")
    }
    private func decision(_ input: [PreflopAction], source: String, note: String, canFold: Bool = true, rounding: Double = 0.000001) throws -> (actions: [PreflopAction], chart: Chart) {
        guard let seat = queue.first else { throw Failure("Preflop has ended") }
        var actions = input
        if canFold && !actions.contains(where: { $0.token.lowercased() == "fold" }) {
            actions.append(PreflopAction(token: "FOLD", file: ActionFile(label: "Fold", path: source), range: [:]))
        }
        let prior = continuationRanges[seat]
        var frequencies = [String: [Double]]()
        for hand in hands {
            let reach = prior?[hand] ?? (prior == nil ? 1 : 0)
            var weights = actions.map { $0.range?[hand] ?? 0 }
            if reach <= 0 { frequencies[hand] = Array(repeating: 0, count: actions.count); continue }
            let sum = weights.reduce(0, +)
            guard sum <= reach * 1.002 + rounding else { throw Failure("Source frequencies exceed earlier reach for \(hand) at \(actor!)") }
            if let fold = actions.firstIndex(where: { $0.token.lowercased() == "fold" }) { weights[fold] += max(0, reach - sum) }
            else { guard abs(sum / reach - 1) <= 0.002 else { throw Failure("Incomplete source frequencies for \(hand)") } }
            let denominator = weights.reduce(0, +)
            frequencies[hand] = weights.map { denominator > 0 ? $0 / denominator : 0 }
        }
        let spot = Spot(id: history.joined(separator: " "), position: actor!, actions: actions.map { $0.file })
        let comboWeights = Dictionary(uniqueKeysWithValues: hands.map { hand in
            (hand, (prior?[hand] ?? (prior == nil ? 1 : 0)) * combinationCount(hand))
        })
        return (actions, Chart(source: source, spot: spot, note: note + " Frequencies conditioned on the player's previous actions. Gray hands are outside current reach.", actions: actions.map { $0.file.label }, frequencies: frequencies, comboWeights: comboWeights))
    }
    private func importedDecision() throws -> (actions: [PreflopAction], chart: Chart) {
        guard let seat = queue.first else { throw Failure("Preflop has ended") }
        if let headsUp = headsUp {
            let limped = history.count >= 2 && history[1].lowercased() == "call"
            let keys = limped ? ["VS_LIMP", "VS_LIMP_RAISE", "VS_LIMP_3BET", "VS_LIMP_4BET", "VS_LIMP_5BET"] : ["SRP", "3BP", "4BP", "5BP", "6BP"]
            guard keys.indices.contains(raises), let spot = headsUp.spots.first(where: { $0.key == keys[raises] }), spot.a.count == 169, spot.b.count == 169 else { throw Failure("No heads-up chart for this line") }
            let path = root.appendingPathComponent("heads-up.json").path + "#" + spot.key
            func action(_ token: String, _ label: String, _ values: [Double]) -> PreflopAction {
                let prior = continuationRanges[seat]
                let range = Dictionary(uniqueKeysWithValues: hands.enumerated().map { i, hand in
                    (hand, (prior?[hand] ?? (prior == nil ? 1 : 0)) * values[i] / 100)
                })
                return PreflopAction(token: token, file: ActionFile(label: label, path: path), range: range)
            }
            var actions = [PreflopAction]()
            if spot.aLabel != nil, let size = spot.sizeTo {
                let token = size >= 100 ? "AllIn" : String(format: "%gbb", size)
                actions.append(action(token, actionLabel(token)!, spot.a))
            }
            let check = spot.bLabel == "Check"
            actions.append(action(check ? "CHECK" : "CALL", check ? "Check" : (spot.bLabel == "Limp" ? "Limp" : "Call"), spot.b))
            return try decision(actions, source: "SolvePoker · MonkerSolver heads-up · 100 BB · 5% rake, 2 BB cap", note: "\(path). Published frequencies retained at source precision.", canFold: spot.canFold)
        }
        guard let cash = cash else { throw Failure("No imported charts") }
        let sourceSeats = Array(["EP1", "EP2", "EP3", "LJ", "HJ", "CO", "BTN", "SB", "BB"].suffix(players))
        let hero = sourceSeats[seat]
        let villain = aggressor.map { sourceSeats[$0] }
        let suffix = villain.map { hero + "vs" + $0 } ?? hero
        let raiseKey: String?, callKey: String
        let size: Double
        let oldBet = committed.max()!
        let inPosition = aggressor.map { (seat + 2) % players > ($0 + 2) % players } ?? false
        switch raises {
        case 0: raiseKey = "Open" + hero; callKey = "Limp" + hero; size = hero == "SB" ? 3 : 2.5
        case 1: raiseKey = "3Bet" + suffix; callKey = "Call" + suffix; size = max(7, oldBet * (inPosition ? 3 : 5))
        case 2: raiseKey = "4Bet" + suffix; callKey = "Call 3Bet" + suffix; size = (oldBet * (inPosition ? 2 : 2.5)).rounded()
        case 3: raiseKey = "5Bet" + suffix; callKey = "Call 4Bet" + suffix; size = 100
        case 4: raiseKey = nil; callKey = "Call 5Bet" + suffix; size = 100
        default: throw Failure("No stored preflop response for this line")
        }
        var actions = [PreflopAction]()
        func add(_ key: String, token: String) {
            guard let range = cash[key], range.values.contains(where: { $0 > 0 }) else { return }
            actions.append(PreflopAction(token: token, file: ActionFile(label: actionLabel(token)!, path: root.appendingPathComponent("nl50-cash.json").path + "#" + key), range: range))
        }
        if let key = raiseKey { add(key, token: size >= 100 ? "AllIn" : String(format: "%gbb", size)) }
        add(callKey, token: "CALL")
        guard !actions.isEmpty else { throw Failure("No stored response for \(actor!) after this line") }
        return try decision(actions, source: "Poker Trainer · Cash 100 BB GTO · NL50-style rake", note: libraryNote + ". 2.5 BB opens; SB 3 BB. Source charts retain the risk of players behind entering.")
    }
}
