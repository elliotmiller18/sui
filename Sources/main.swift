import AppKit

let help = """
Sui — native preflop range viewer + TexasSolver runner

  sui [view] [--position BTN] [--spot ID]
  sui list [--ranges DIR] [--position BTN]
  sui export --ranges DIR --position BTN --spot ID
  sui solve --solver-home DIR --input FILE --out NEW_DIR [--timeout SECONDS]
  sui postflop --board Qs,8d,7h --pot 6 --stack 97.5 --ip-range FILE --oop-range FILE
      [--solver-home DIR] [--out NEW_DIR] [--timeout SECONDS]

postflop solves a 1/3 and 1.5x pot tree (capped at all-in) and opens its clickable result.
Solves have no time limit unless --timeout is supplied.
--solver-optimizations baseline|safe|memory|all|FLAG,... selects experimental solver paths.
Omit it for baseline; SUI_SOLVER_OPTIMIZATIONS also works when launching the app.
Range arguments accept file paths or range text (e.g. AA,AKs).

view/export options:
  --remainder unassigned|fold|check   Default: fold
  --raise-bb N                      Label unspecified raises with an assumed size

list and export write JSON to stdout. Errors go to stderr with exit code 1.
--spot is an exact ID from list. Export requires it when multiple spots match.
The app starts UTG with bundled 100bb NL50-style charts; Table selects 2–9 players.
list/export inspect the original six-player NL500 files or a custom folder.
Preflop is imported library data; TexasSolver itself only solves postflop.
"""
func main() throws {
    var args = Array(CommandLine.arguments.dropFirst()).filter { !$0.hasPrefix("-psn_") }
    if args.contains("--help") || args.contains("-h") { print(help); return }
    let command = args.first.map { !$0.hasPrefix("--") } == true ? args.removeFirst() : "view"
    guard ["view", "list", "export", "solve", "postflop"].contains(command) else { throw Failure("Unknown command: \(command)\n\(help)") }
    var options = [String: String]()
    let allowed: Set<String>
    if command == "solve" { allowed = ["--solver-home", "--input", "--out", "--timeout"] }
    else if command == "postflop" { allowed = ["--solver-home", "--board", "--pot", "--stack", "--ip-range", "--oop-range", "--out", "--timeout"] }
    else if command == "view" { allowed = ["--position", "--spot", "--remainder", "--raise-bb"] }
    else { allowed = ["--ranges", "--position", "--spot", "--remainder", "--raise-bb"] }
    while !args.isEmpty {
        let key = args.removeFirst()
        guard allowed.contains(key) || (["view", "solve", "postflop"].contains(command) && key == "--solver-optimizations"), !args.isEmpty, !args[0].hasPrefix("--"), options[key] == nil else { throw Failure("Unknown, repeated, or incomplete option: \(key)") }
        options[key] = args.removeFirst()
    }
    func url(_ path: String) -> URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL }
    func solveTimeout() throws -> Double? {
        guard let value = options["--timeout"] else { return nil }
        guard let seconds = Double(value), seconds.isFinite, seconds > 0 else { throw Failure("--timeout must be positive") }
        return seconds
    }
    solverOptimizationOverride = options["--solver-optimizations"]
    if command == "solve" {
        guard let home = options["--solver-home"].map(url) ?? defaultSolver(), let input = options["--input"], let output = options["--out"] else { throw Failure("solve requires --input FILE --out NEW_DIR and a solver installation") }
        let seconds = try solveTimeout()
        try runSolver(home: home, input: url(input), output: url(output), seconds: seconds); return
    }
    if command == "postflop" {
        guard let home = options["--solver-home"].map(url) ?? defaultSolver(),
              let board = options["--board"], let pot = options["--pot"], let stack = options["--stack"],
              let ip = options["--ip-range"], let oop = options["--oop-range"] else { throw Failure("postflop requires --board, --pot, --stack, --ip-range, --oop-range and a solver installation") }
        let input = try PostflopInput(board: board, pot: pot, stack: stack, ip: ip, oop: oop)
        let output = options["--out"].map(url) ?? FileManager.default.temporaryDirectory.appendingPathComponent("sui-solves/" + UUID().uuidString)
        let solved = try solvePostflop(input, home: home, output: output, timeout: try solveTimeout())
        print(output.path)
        let app = NSApplication.shared
        let delegate = Desktop(root: home.appendingPathComponent("ranges/qb_ranges/100bb 2.5x 500rake"), spots: [], initial: nil, remainder: "fold", raiseBB: nil, postflop: solved)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        return
    }
    let root: URL
    if let path = options["--ranges"] { root = url(path) }
    else if let home = defaultSolver() { root = home.appendingPathComponent("ranges/qb_ranges/100bb 2.5x 500rake") }
    else { throw Failure("Bundled solver missing; run scripts/build.sh") }
    let all = try catalog(root)
    let matching = all.filter { options["--position"] == nil || $0.position == position(options["--position"]!) }
    if command == "list" { print(try json(matching)); return }
    guard !matching.isEmpty else { throw Failure("No supported ranges for this position in \(root.path)") }
    let selected: Spot
    if let id = options["--spot"] {
        guard let found = matching.first(where: { $0.id == id }) else { throw Failure("Spot not found. Use sui list to obtain an exact --spot ID.") }
        selected = found
    } else if command == "export" && matching.count > 1 { throw Failure("Multiple spots match. Use sui list, then --spot with the exact ID.") }
    else { selected = matching.min { $0.id.count < $1.id.count }! }
    let remainder = options["--remainder"] ?? "fold"
    let current = try chart(selected, remainder: remainder, raiseBB: options["--raise-bb"])
    if command == "export" { print(try json(current)); return }
    let app = NSApplication.shared
    let delegate = Desktop(root: root, spots: all, initial: options["--spot"] != nil || options["--position"] != nil ? selected : nil, remainder: remainder, raiseBB: options["--raise-bb"])
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
do { try main() }
catch { FileHandle.standardError.write(Data("sui: \(error)\n".utf8)); exit(1) }
