import Foundation

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
func position(_ text: String) -> String { text.uppercased() == "B" ? "BTN" : text.uppercased() }
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
struct Chart: Codable {
    let source: String
    let spot: Spot
    let note: String
    let actions: [String]
    let frequencies: [String: [Double]]
}
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
