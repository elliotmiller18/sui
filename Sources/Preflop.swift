import Foundation

// The flat 100bb library omits folds by players who have not yet invested.
// Preserve folds after an earlier action so distinct response lines never merge.
func historyKey(_ tokens: [String]) -> String {
    var invested = Set<String>(), result = [String]()
    for i in stride(from: 0, to: tokens.count - 1, by: 2) {
        let player = tokens[i].uppercased(), action = tokens[i+1].lowercased()
        if action != "fold" || invested.contains(player) { result += [player, action] }
        if action != "fold" { invested.insert(player) }
    }
    return result.joined(separator: "_")
}
struct PreflopAction {
    let token: String
    let file: ActionFile
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
    static let seats = ["UTG", "MP", "CO", "BTN", "SB", "BB"]
    private var continuationRanges = [Int: [String: Double]]()
    private var rangeSources = [String: String]()
    private var index: [String: [PreflopAction]] = [:]
    private(set) var history = [String]()
    private(set) var queue = Array(0..<6)
    private(set) var folded = Set<Int>()
    private(set) var allin = Set<Int>()
    private(set) var committed = [0.0, 0, 0, 0, 0.5, 1]
    var actor: String? { queue.first.map { Self.seats[$0] } }
    var finished: Bool { queue.isEmpty || folded.count == 5 }
    var pot: Double { committed.reduce(0,+) }
    var ending: String? {
        if folded.count == 5 { return "Hand ended — \(Self.seats[(0..<6).first { !folded.contains($0) }!]) wins." }
        if finished && (0..<6).filter({ !folded.contains($0) }).allSatisfy({ committed[$0] >= 100 - 0.001 }) {
            return "All-in called — no further decisions."
        }
        return nil
    }
    var message: String {
        if let ending = ending { return ending }
        if finished { return "Postflop" }
        return "\(actor!) to act · Pot \(String(format: "%.1f", pot)) BB"
    }
    init(root: URL) throws {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { throw Failure("Cannot read range library") }
        for case let file as URL in walker where file.pathExtension == "txt" {
            let tokens = file.deletingPathExtension().lastPathComponent.components(separatedBy: "_")
            guard tokens.count >= 2, tokens.count % 2 == 0,
                  Self.seats.contains(tokens[tokens.count-2]),
                  let label = actionLabel(tokens.last!) else { continue }
            let key = historyKey(Array(tokens.dropLast(2))) + "|" + tokens[tokens.count-2]
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
        return (index[historyKey(history) + "|" + actor] ?? []).sorted { $0.file.label < $1.file.label }
    }
    func currentChart() throws -> Chart? {
        if finished { return nil }
        let options = options()
        guard !options.isEmpty else { throw Failure("No stored response for \(actor!) after this line. This library does not cover every branch.") }
        return try chart(Spot(id: history.joined(separator: " "), position: actor!, actions: options.map { $0.file }), remainder: "fold", raiseBB: nil)
    }
    func handoff() throws -> PostflopHandoff {
        guard finished else { throw Failure("Preflop betting is not complete") }
        // Postflop order starts at SB, then BB, then UTG through BTN.
        let live = [4,5,0,1,2,3].filter { !folded.contains($0) }
        guard live.count == 2 else { throw Failure("Postflop solving supports two players; \(live.count) remain.") }
        let effective = live.map { 100 - committed[$0] }.min()!
        guard effective > 0 else { throw Failure("All-in called — no further betting decisions.") }
        guard let oop = continuationRanges[live[0]], let ip = continuationRanges[live[1]],
              oop.values.contains(where: { $0 > 0 }), ip.values.contains(where: { $0 > 0 }) else { throw Failure("No continuation range for a remaining player") }
        return PostflopHandoff(oopSeat: Self.seats[live[0]], ipSeat: Self.seats[live[1]], pot: pot, stack: effective,
                              oopRange: oop, ipRange: ip, history: history, rangeSources: rangeSources.filter { [Self.seats[live[0]], Self.seats[live[1]]].contains($0.key) })
    }
    func advance(_ label: String) throws {
        guard let seat = queue.first, !finished else { throw Failure("Preflop has ended") }
        let selected = options().first { $0.file.label == label }
        guard selected != nil || label == "Fold" else { throw Failure("Action has no stored range") }
        let token = selected?.token ?? "FOLD"
        // These files describe the player's range after the named line. Keep the
        // latest range as-is; multiplying earlier chart weights would count reach twice.
        let selectedRange: [String: Double]?
        if token.lowercased() != "fold", let selected = selected {
            selectedRange = try parseRange(String(contentsOfFile: selected.file.path, encoding: .utf8))
        } else { selectedRange = nil }
        let oldBet = committed.max()!
        queue.removeFirst()
        if token.lowercased() == "fold" { folded.insert(seat) }
        else if token.lowercased() == "call" {
            guard committed[seat] < oldBet else { throw Failure("Nothing to call") }
            committed[seat] = oldBet
        } else if token.lowercased() == "allin" { committed[seat] = 100; allin.insert(seat) }
        else if token.lowercased().hasSuffix("bb"), let amount = Double(token.dropLast(2)), amount > oldBet { committed[seat] = amount }
        else { throw Failure("Unsupported preflop action: \(token)") }
        if let selectedRange = selectedRange {
            continuationRanges[seat] = selectedRange
            rangeSources[Self.seats[seat]] = selected!.file.path
        }
        if committed[seat] >= 100 - 0.001 { allin.insert(seat) }
        history += [Self.seats[seat], token]
        // Once two players enter voluntarily, all other seats auto-fold.
        // Blinds remain in the pot, but do not count as entering the hand.
        let entered = Set(continuationRanges.keys).subtracting(folded)
        if entered.count == 2 {
            for other in 0..<6 where !entered.contains(other) && !folded.contains(other) {
                folded.insert(other)
                history += [Self.seats[other], "FOLD"]
            }
            queue.removeAll { folded.contains($0) || allin.contains($0) }
        }
        if committed[seat] > oldBet {
            queue = (1..<6).map { (seat + $0) % 6 }.filter { !folded.contains($0) && !allin.contains($0) }
        }
        if folded.count == 5 { queue = [] }
        if queue.count == 1, let last = queue.first, committed[last] == committed.max()! { queue = [] }
    }
}
