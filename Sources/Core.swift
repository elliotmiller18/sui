import Foundation

// Written for Sui by us: retain the chosen action's display label/color and BB amount.
struct HandHistoryAction: Codable, Equatable {
    let street: String
    let board: [String]
    let seat: String
    let action: String
    let amountBB: Double?
    var kind: String {
        let lower = action.lowercased()
        if lower.contains("all-in") { return "All-in" }
        if lower.contains("raise") { return "Raise" }
        if lower.contains("bet") { return "Bet" }
        if lower.contains("limp") { return "Limp" }
        if lower.contains("call") { return "Call" }
        if lower.contains("check") { return "Check" }
        return "Fold"
    }
    var amountText: String { amountBB.map { String(format: "%.4g BB", $0) } ?? "" }
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ text: String) { description = text }
}
let ranks = Array("AKQJT98765432").map(String.init)
let hands: [String] = {
    var result: [String] = []
    for row in 0..<13 {
        for col in 0..<13 {
            let high = ranks[min(row, col)]
            let low = ranks[max(row, col)]
            let suffix = row == col ? "" : (row < col ? "s" : "o")
            result.append(high + low + suffix)
        }
    }
    return result
}()
func canonical(_ text: String) throws -> [String] {
    let c = Array(text).map(String.init)
    guard (2...3).contains(c.count), let a = ranks.firstIndex(of: c[0]), let b = ranks.firstIndex(of: c[1]) else { throw Failure("Invalid hand: \(text)") }
    if a == b {
        guard c.count == 2 else { throw Failure("Invalid pair: \(text)") }
        return [c[0] + c[1]]
    }
    let base = ranks[min(a,b)] + ranks[max(a,b)]
    if c.count == 2 { return [base + "s", base + "o"] }
    guard c[2] == "s" || c[2] == "o" else { throw Failure("Invalid hand: \(text)") }
    return [base + c[2]]
}
func parseRange(_ text: String) throws -> [String: Double] {
    var result = [String: Double]()
    for token in text.split(whereSeparator: { $0 == "," || $0.isWhitespace }) {
        let parts = token.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2, let weight = parts.count == 1 ? 1.0 : Double(parts[1]), weight.isFinite, (0...1).contains(weight) else { throw Failure("Invalid range weight: \(token)") }
        for hand in try canonical(String(parts[0])) {
            guard result[hand] == nil else { throw Failure("Duplicate hand: \(hand)") }
            result[hand] = weight
        }
    }
    guard !result.isEmpty else { throw Failure("Range file is empty") }
    return result
}
// Written for Sui by us: keep old library filenames compatible with the HJ label.
func position(_ text: String) -> String {
    switch text.uppercased() {
    case "B": return "BTN"
    case "MP": return "HJ"
    default: return text.uppercased()
    }
}
struct ActionFile: Codable { let label: String; let path: String }
struct Spot: Codable {
    let id: String
    let position: String
    var actions: [ActionFile]
}
func actionLabel(_ raw: String) -> String? {
    switch raw.lowercased() {
    case "raise": return "Raise (size unspecified)"
    case "call": return "Call"
    case "fold": return "Fold"
    case "check": return "Check"
    case "allin": return "All-in"
    default:
        if raw.lowercased().hasSuffix("bb"), Double(raw.dropLast(2)) != nil { return "Raise to \(raw)" }
        return nil
    }
}
// Only sibling action files at the same decision are combined. A *_range file
// describes one player's range at a leaf, not a set of action frequencies.
func catalog(_ root: URL) throws -> [Spot] {
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { throw Failure("Ranges folder does not exist: \(root.path)") }
    guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { throw Failure("Cannot read ranges folder") }
    var groups = [String: Spot]()
    for case let file as URL in walker where file.pathExtension.lowercased() == "txt" {
        let relative = String(file.path.dropFirst(root.path.count + 1))
        let stem = file.deletingPathExtension().lastPathComponent
        let bits = stem.components(separatedBy: "_")
        let parent = (relative as NSString).deletingLastPathComponent
        guard bits.count >= 2 else { continue }
        let pos: String, key: String, label: String
        if bits.last!.lowercased() == "range", bits.count == 2 {
            pos = position(bits[0]); key = relative; label = "In range"
        } else if let action = actionLabel(bits.last!) {
            pos = position(bits[bits.count - 2])
            let history = bits.dropLast(2).joined(separator: "_")
            key = (parent.isEmpty ? "." : parent) + (history.isEmpty ? "" : "/" + history) + " | " + pos
            label = action
        } else { continue }
        guard ["UTG", "LJ", "MP", "HJ", "CO", "BTN", "SB", "BB"].contains(pos) else { continue }
        if groups[key] == nil { groups[key] = Spot(id: key, position: pos, actions: []) }
        groups[key]!.actions.append(ActionFile(label: label, path: file.path))
    }
    return groups.values.map { spot in
        var s = spot
        s.actions.sort { $0.label < $1.label }
        return s
    }.sorted { $0.id < $1.id }
}
// Written for Sui by us: suit cells distinguish blocked/unreached hands from folds.
struct ComboBreakdown {
    enum Status { case available, blocked, outsideRange, unavailable }
    let cards: [String]
    let frequencies: [Double]
    let status: Status
    let exact: Bool
    var key: String { cards.sorted().joined() }
    var displayName: String {
        let symbols = ["s": "♠", "h": "♥", "d": "♦", "c": "♣"]
        return cards.map { String($0.prefix(1)) + (symbols[String($0.suffix(1))] ?? "") }.joined(separator: " ")
    }
    var unavailableMessage: String? {
        switch status {
        case .available: return nil
        case .blocked: return "Blocked by board"
        case .outsideRange: return "Outside current range"
        case .unavailable: return "Strategy unavailable"
        }
    }
    func summary(actions: [String]) -> String {
        if let reason = unavailableMessage { return displayName + "\n" + reason }
        let lines = zip(actions, frequencies).map { "\($0.0): \(String(format: "%.1f%%", $0.1 * 100))" }
        let origin = exact ? "Exact combo strategy" : "Chart frequencies shared across suits"
        return ([displayName] + lines + [origin]).joined(separator: "\n")
    }
}
func suitCombinations(_ hand: String) -> [[String]] {
    guard hands.contains(hand) else { return [] }
    let ranks = Array(hand).map(String.init), suits = ["s", "h", "d", "c"]
    if hand.hasSuffix("s") { return suits.map { [ranks[0] + $0, ranks[1] + $0] } }
    if hand.hasSuffix("o") {
        return suits.flatMap { first in suits.filter { $0 != first }.map { [ranks[0] + first, ranks[1] + $0] } }
    }
    return suits.indices.flatMap { first in suits.indices.filter { $0 > first }.map { [ranks[0] + suits[first], ranks[1] + suits[$0]] } }
}
struct Chart: Codable {
    let source: String
    let spot: Spot
    let note: String
    let actions: [String]
    let frequencies: [String: [Double]]
    // Written for Sui by us: carry actual combo reach for whole-range summaries.
    var comboWeights: [String: Double]? = nil
    var comboFrequencies: [String: [Double]]? = nil
    var comboReach: [String: Double]? = nil
    var board: [String]? = nil
    func combinations(for hand: String) -> [ComboBreakdown] {
        suitCombinations(hand).map { cards in
            let key = cards.sorted().joined()
            let exact = comboFrequencies != nil
            let values = comboFrequencies?[key] ?? (exact ? [] : (frequencies[hand] ?? []))
            let status: ComboBreakdown.Status
            if cards.contains(where: { board?.contains($0) == true }) { status = .blocked }
            else if let reach = comboReach, (reach[key] ?? 0) <= 0 { status = .outsideRange }
            else if values.count != actions.count { status = .unavailable }
            else if values.reduce(0, +) <= 0 { status = .outsideRange }
            else { status = .available }
            return ComboBreakdown(cards: cards, frequencies: status == .available ? values : [], status: status, exact: exact)
        }
    }
    var actionBreakdown: [Double] {
        var totals = Array(repeating: 0.0, count: actions.count), denominator = 0.0
        for hand in hands {
            guard let values = frequencies[hand], values.count == actions.count, values.reduce(0, +) > 0 else { continue }
            let weight = comboWeights?[hand] ?? (comboWeights == nil ? combinationCount(hand) : 0)
            denominator += weight
            for i in totals.indices { totals[i] += values[i] * weight }
        }
        return totals.map { denominator > 0 ? $0 / denominator : 0 }
    }
}
func combinationCount(_ hand: String) -> Double { hand.count == 2 ? 6 : (hand.hasSuffix("s") ? 4 : 12) }
func chart(_ spot: Spot, remainder: String, raiseBB: String?) throws -> Chart {
    guard ["unassigned", "fold", "check"].contains(remainder) else { throw Failure("--remainder must be unassigned, fold, or check") }
    if let bb = raiseBB { guard let n = Double(bb), n.isFinite, n > 0 else { throw Failure("--raise-bb must be positive") } }
    let ranges = try spot.actions.map { try parseRange(String(contentsOfFile: $0.path, encoding: .utf8)) }
    var labels = spot.actions.map { $0.label == "Raise (size unspecified)" && raiseBB != nil ? "Raise to \(raiseBB!) bb (assumed)" : $0.label }
    guard Set(labels).count == labels.count else { throw Failure("Duplicate action labels in \(spot.id)") }
    let residual = remainder.capitalized
    let residualIndex = labels.firstIndex(of: residual) ?? labels.count
    if residualIndex == labels.count { labels.append(residual) }
    var values = [String: [Double]]()
    for hand in hands {
        var row = ranges.map { $0[hand] ?? 0 }
        let sum = row.reduce(0,+)
        guard sum <= 1.002 else { throw Failure("\(hand) totals \(String(format: "%.1f", sum * 100))% in \(spot.id). These files cannot be combined as action frequencies.") }
        // Permit small export rounding only; never silently normalize conflicting ranges.
        if sum > 1 { row = row.map { $0 / sum } }
        if residualIndex == row.count { row.append(0) }
        row[residualIndex] += max(0, 1 - sum)
        values[hand] = row
    }
    return Chart(source: "Imported preflop library — not a fresh solve", spot: spot,
                 note: "File weights shown as supplied; not conditioned on earlier actions. Missing weight: \(residual.lowercased()).", actions: labels, frequencies: values)
}
func json<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
func defaultSolver() -> URL? {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let candidates = [
        Bundle.main.resourceURL?.appendingPathComponent("solver"),
        executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/solver"),
        executable.deletingLastPathComponent().appendingPathComponent("Sui.app/Contents/Resources/solver")
    ].compactMap { $0 }
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0.appendingPathComponent("console_solver").path) && FileManager.default.fileExists(atPath: $0.appendingPathComponent("resources").path) }
}
