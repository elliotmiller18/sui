import Foundation
import Darwin

final class SolverControl {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func attach(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        self.process = process
        if cancelled && process.isRunning { process.terminate() }
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let process = process, process.isRunning { process.terminate() }
    }
}

// Executes in a new output directory, never in the installation or a prior run.
func runSolver(home: URL, input: URL, output: URL, seconds: Double, control: SolverControl? = nil, announce: Bool = true) throws {
    let fm = FileManager.default
    guard seconds.isFinite, seconds > 0 else { throw Failure("--timeout must be positive") }
    guard !fm.fileExists(atPath: output.path) else { throw Failure("Output directory already exists; choose a fresh --out directory") }
    let binary = home.appendingPathComponent("console_solver")
    guard fm.isExecutableFile(atPath: binary.path) else { throw Failure("Missing executable: \(binary.path)") }
    let original = try String(contentsOf: input, encoding: .utf8)
    let lines = original.split(whereSeparator: \.isNewline).map(String.init)
    guard let boardLine = lines.first(where: { $0.hasPrefix("set_board ") }), (3...5).contains(boardLine.dropFirst(10).split(separator: ",").count) else { throw Failure("TexasSolver requires a 3–5 card board. Use preflop charts for preflop.") }
    guard lines.contains("start_solve") else { throw Failure("Input must contain start_solve") }
    try fm.createDirectory(at: output, withIntermediateDirectories: true)
    try fm.createSymbolicLink(at: output.appendingPathComponent("resources"), withDestinationURL: home.appendingPathComponent("resources"))
    let script = lines.filter { !$0.hasPrefix("dump_result") }.joined(separator: "\n") + "\ndump_result result.json\n"
    try script.write(to: output.appendingPathComponent("input.txt"), atomically: true, encoding: .utf8)
    let logURL = output.appendingPathComponent("solver.log")
    fm.createFile(atPath: logURL.path, contents: nil)
    let log = try FileHandle(forWritingTo: logURL); defer { try? log.close() }
    let process = Process(); process.executableURL = binary
    process.arguments = ["-i", "input.txt", "-r", "resources"]
    process.currentDirectoryURL = output
    process.standardInput = FileHandle.nullDevice; process.standardOutput = log; process.standardError = log
    let done = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in done.signal() }
    try process.run()
    control?.attach(process)
    if done.wait(timeout: .now() + seconds) == .timedOut {
        process.terminate()
        if done.wait(timeout: .now() + 2) == .timedOut { kill(process.processIdentifier, SIGKILL) }
        throw Failure("Solver timed out after \(seconds)s. No strategy accepted. Inspect \(logURL.path)")
    }
    guard process.terminationStatus == 0 else { throw Failure("Solver exited \(process.terminationStatus). Inspect \(logURL.path)") }
    let result = output.appendingPathComponent("result.json")
    guard let data = try? Data(contentsOf: result), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["strategy"] != nil else { throw Failure("Solver produced no valid strategy. Inspect \(logURL.path)") }
    if announce { print(result.path) }
}

// Read only the log tail, so polling stays cheap even during resource loading.
func solverProgress(at output: URL) -> String {
    guard let file = try? FileHandle(forReadingFrom: output.appendingPathComponent("solver.log")) else { return "Preparing solver…" }
    defer { try? file.close() }
    guard let end = try? file.seekToEnd() else { return "Preparing solver…" }
    try? file.seek(toOffset: end > 65536 ? end - 65536 : 0)
    let data = (try? file.readToEnd()) ?? Data()
    let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n").dropLast()
    let iteration = lines.last { $0.hasPrefix("Iter: ") }.map { String($0.dropFirst(6)) }
    let accuracy = lines.last { $0.hasPrefix("Total exploitability ") }.flatMap { Double($0.split(separator: " ").dropFirst(2).first ?? "") }
    var parts = [String]()
    if FileManager.default.fileExists(atPath: output.appendingPathComponent("result.json").path) { parts.append("Exporting strategy…") }
    if let iteration = iteration { parts.append("Iteration \(iteration) / 200") }
    // Written for Sui by us: match the interactive solve target in PostflopInput.
    if let accuracy = accuracy { parts.append(String(format: "Exploitability %.3f%% · target 2%%", accuracy)) }
    return parts.isEmpty ? "Preparing solver…" : parts.joined(separator: "\n")
}
