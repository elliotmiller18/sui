import Foundation
import Darwin

// Optional CLI experiment selection; fixed before any solver is launched.
var solverOptimizationOverride: String?

// Written for Sui by us: the initial budget stays conservative, but is adjustable.
var defaultSolverStorageBudgetGiB: Double {
    max(0.25, min(8, Double(ProcessInfo.processInfo.physicalMemory) / 1073741824 / 2))
}
struct SolverStorageLimit: Error, CustomStringConvertible {
    let requiredGiB: Double
    let budgetGiB: Double
    let logURL: URL
    let message: String
    var suggestedBudgetGiB: Double { max(ceil(requiredGiB), floor(budgetGiB) + 1) }
    var description: String { message + " Inspect " + logURL.path }

    init?(log: String, budgetGiB: Double, logURL: URL) {
        let lines = log.components(separatedBy: .newlines)
        guard let message = lines.first(where: { $0.hasPrefix("SUI_MEMORY_LIMIT:") }) else { return nil }
        func number(after prefix: String) -> Double? {
            guard let line = lines.first(where: { $0.hasPrefix(prefix) }),
                  let value = Double(line.dropFirst(prefix.count).split(separator: " ").first ?? ""),
                  value.isFinite, value > 0 else { return nil }
            return value
        }
        // New engines report full precision; old engines print MiB to one decimal.
        // Include that rounding uncertainty when suggesting a legacy retry budget.
        let exact = number(after: "SUI_MEMORY_REQUIRED_MB: ")
        let legacy = number(after: "Sui estimated strategy storage: ").map { $0 + 0.05 }
        guard let requiredMB = exact ?? legacy else { return nil }
        self.requiredGiB = requiredMB / 1024
        self.budgetGiB = budgetGiB; self.logURL = logURL
        self.message = String(message.dropFirst("SUI_MEMORY_LIMIT: ".count)).replacingOccurrences(of: "strategy storage", with: "strategy RAM").replacingOccurrences(of: "solver budget", with: "solver RAM budget")
    }
}

struct SolverCancelled: Error, CustomStringConvertible {
    var description: String { "Solve cancelled." }
}
final class SolverControl {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var finishRequested = false
    private var stopFile: URL?
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldStop = cancelled
        lock.unlock()
        if shouldStop { stop(process) }
    }
    func finish() throws {
        lock.lock(); finishRequested = true; let file = stopFile; lock.unlock()
        if let file = file { try Data().write(to: file, options: .atomic) }
    }
    func attachStopFile(_ file: URL) throws {
        lock.lock(); stopFile = file; let requested = finishRequested; lock.unlock()
        if requested { try Data().write(to: file, options: .atomic) }
    }
    func cancel() {
        lock.lock()
        cancelled = true
        let active = process
        lock.unlock()
        if let active = active { stop(active) }
    }
    // Written for Sui by us: Reset must also stop a solver that ignores SIGTERM.
    private func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}

// Executes in a new output directory, never in the installation or a prior run.
func runSolver(home: URL, input: URL, output: URL, seconds: Double? = nil, control: SolverControl? = nil, announce: Bool = true, storageBudgetGiB: Double = defaultSolverStorageBudgetGiB, livePreview: Bool = false) throws {
    let fm = FileManager.default
    guard storageBudgetGiB.isFinite, storageBudgetGiB > 0, (storageBudgetGiB * 1024).isFinite else { throw Failure("Solver RAM budget must be a positive GiB amount") }
    if let seconds = seconds {
        guard seconds.isFinite, seconds > 0 else { throw Failure("--timeout must be positive") }
    }
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
    // Written for Sui by us: pass the chosen budget; never silently raise it.
    var environment = ProcessInfo.processInfo.environment
    environment["SUI_SOLVER_MEMORY_LIMIT_MB"] = String(storageBudgetGiB * 1024)
    if let flags = solverOptimizationOverride { environment["SUI_SOLVER_OPTIMIZATIONS"] = flags }
    if livePreview { environment["SUI_SOLVER_PREVIEW_PATH"] = "preview.json"; environment["SUI_SOLVER_EXPORT_EV"] = "1" }
    else { environment.removeValue(forKey: "SUI_SOLVER_PREVIEW_PATH") }
    if let control = control {
        environment["SUI_SOLVER_STOP_PATH"] = "stop-request"
        try control.attachStopFile(output.appendingPathComponent("stop-request"))
    } else { environment.removeValue(forKey: "SUI_SOLVER_STOP_PATH") }
    process.environment = environment
    process.arguments = ["-i", "input.txt", "-r", "resources"]
    process.currentDirectoryURL = output
    process.standardInput = FileHandle.nullDevice; process.standardOutput = log; process.standardError = log
    let done = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in done.signal() }
    try process.run()
    control?.attach(process)
    if let seconds = seconds {
        if done.wait(timeout: .now() + seconds) == .timedOut {
            process.terminate()
            if done.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                done.wait()
            }
            throw Failure("Solver timed out after \(seconds)s. No strategy accepted. Inspect \(logURL.path)")
        }
    } else {
        done.wait()
    }
    if control?.isCancelled == true { throw SolverCancelled() }
    if process.terminationStatus != 0 {
        let contents = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        if let limit = SolverStorageLimit(log: contents, budgetGiB: storageBudgetGiB, logURL: logURL) { throw limit }
        if let message = contents.components(separatedBy: .newlines).first(where: { $0.hasPrefix("SUI_MEMORY_LIMIT:") }) {
            throw Failure(String(message.dropFirst("SUI_MEMORY_LIMIT: ".count)) + " Inspect \(logURL.path)")
        }
        if process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGKILL {
            throw Failure("Solver was killed (SIGKILL), possibly because it ran out of memory. No strategy accepted. Inspect \(logURL.path)")
        }
        throw Failure("Solver exited \(process.terminationStatus). Inspect \(logURL.path)")
    }
    let result = output.appendingPathComponent("result.json")
    guard let data = try? Data(contentsOf: result), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["strategy"] != nil else { throw Failure("Solver produced no valid strategy. Inspect \(logURL.path)") }
    if announce { print(result.path) }
}

// Read only the log tail, so polling stays cheap even during resource loading.
func solverProgress(at output: URL) -> String {
    guard let file = try? FileHandle(forReadingFrom: output.appendingPathComponent("solver.log")) else { return "Iteration 0 / 200" }
    defer { try? file.close() }
    guard let end = try? file.seekToEnd() else { return "Iteration 0 / 200" }
    try? file.seek(toOffset: end > 65536 ? end - 65536 : 0)
    let data = (try? file.readToEnd()) ?? Data()
    let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n").dropLast()
    let iteration = lines.last { $0.hasPrefix("SUI_ITERATION: ") }.map { String($0.dropFirst(15)) }
        ?? lines.last { $0.hasPrefix("Iter: ") }.map { String($0.dropFirst(6)) }
    let measuredAt = lines.lastIndex { $0.hasPrefix("Total exploitability ") }.flatMap { index in
        lines[...index].last { $0.hasPrefix("Iter: ") }.map { String($0.dropFirst(6)) }
    }
    let accuracy = lines.last { $0.hasPrefix("Total exploitability ") }.flatMap { Double($0.split(separator: " ").dropFirst(2).first ?? "") }
    var parts = [String]()
    if FileManager.default.fileExists(atPath: output.appendingPathComponent("result.json").path) { parts.append("Exporting strategy…") }
    if let iteration = iteration { parts.append("Iteration \(iteration) / 200") }
    // Written for Sui by us: match the interactive solve target in PostflopInput.
    if let accuracy = accuracy { parts.append(String(format: "Exploitability %.3f%% · target 2%%", accuracy) + (measuredAt.map { " (iteration \($0))" } ?? "")) }
    return parts.isEmpty ? "Iteration 0 / 200" : parts.joined(separator: "\n")
}
