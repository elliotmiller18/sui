import Foundation

@main struct BudgetChecks {
    static func main() throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("sui-budget-" + UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let logURL = directory.appendingPathComponent("solver.log")
        let message = "SUI_MEMORY_LIMIT: Estimated strategy storage 19.0 GiB exceeds the 8.0 GiB solver budget."
        let exact = SolverStorageLimit(log: "SUI_MEMORY_REQUIRED_MB: 19497.0000001\n" + message, budgetGiB: 8, logURL: logURL)!
        assert(exact.suggestedBudgetGiB == 20)
        let legacy = SolverStorageLimit(log: "Sui estimated strategy storage: 19497.0 MiB\n" + message, budgetGiB: 8, logURL: logURL)!
        assert(legacy.suggestedBudgetGiB == 20)
        let boundary = SolverStorageLimit(log: "SUI_MEMORY_REQUIRED_MB: 20480.00001\n" + message, budgetGiB: 20, logURL: logURL)!
        assert(boundary.suggestedBudgetGiB == 21)
        assert(SolverStorageLimit(log: message, budgetGiB: 8, logURL: logURL) == nil)
        assert(SolverStorageLimit(log: "SUI_MEMORY_REQUIRED_MB: nan\n" + message, budgetGiB: 8, logURL: logURL) == nil)
        assert(SolverStorageLimit(log: "SUI_MEMORY_REQUIRED_MB: 19497\nOther failure", budgetGiB: 8, logURL: logURL) == nil)

        let home = directory.appendingPathComponent("fake-solver")
        try fm.createDirectory(at: home.appendingPathComponent("resources"), withIntermediateDirectories: true)
        let binary = home.appendingPathComponent("console_solver")
        let script = """
        #!/bin/sh
        printf '%s' "$SUI_SOLVER_MEMORY_LIMIT_MB" > budget.txt
        if [ "$SUI_SOLVER_MEMORY_LIMIT_MB" != '20480.0' ]; then
            printf 'SUI_MEMORY_REQUIRED_MB: 19497.0000001\\nSUI_MEMORY_LIMIT: Estimated strategy storage 19.0 GiB exceeds the 8.0 GiB solver budget.\\n'
            exit 1
        fi
        printf '%s' '{"node_type":"action_node","player":1,"actions":["CHECK"],"strategy":{"actions":["CHECK"],"strategy":{"JcTc":[1]}}}' > result.json
        """
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        var input = try PostflopInput(board: "Qs,8d,7h,2c,3s", pot: "6.5", stack: "20.5", ip: "T9s", oop: "JTs,43s")
        input.betSizes = [.quarter, .allin]; input.storageBudgetGiB = 8
        let first = directory.appendingPathComponent("first")
        do {
            _ = try solvePostflop(input, home: home, output: first)
            fatalError("Budget failure was not reported")
        } catch let failure as SolverStorageLimit {
            assert(failure.suggestedBudgetGiB == 20 && failure.logURL.path == first.appendingPathComponent("solver.log").path)
            input.storageBudgetGiB = failure.suggestedBudgetGiB
        }
        let retry = directory.appendingPathComponent("retry")
        let solved = try solvePostflop(input, home: home, output: retry)
        assert(solved.storageBudgetGiB == 20 && solved.betSizes == input.betSizes)
        let environmentBudget = try String(contentsOf: retry.appendingPathComponent("budget.txt"), encoding: .utf8)
        assert(environmentBudget == "20480.0")
        let firstScript = try String(contentsOf: first.appendingPathComponent("input.txt"), encoding: .utf8)
        let retryScript = try String(contentsOf: retry.appendingPathComponent("input.txt"), encoding: .utf8)
        assert(firstScript == retryScript)
        let saved = try JSONDecoder().decode(PostflopInput.self, from: Data(contentsOf: retry.appendingPathComponent("setup.json")))
        assert(saved.storageBudgetGiB == 20)
        let request = directory.appendingPathComponent("request.txt")
        try input.script().write(to: request, atomically: true, encoding: .utf8)
        for budget in [0, -1, Double.nan, Double.infinity, Double.greatestFiniteMagnitude] {
            let output = directory.appendingPathComponent(UUID().uuidString)
            do {
                try runSolver(home: home, input: request, output: output, seconds: 1, storageBudgetGiB: budget)
                fatalError("Invalid budget accepted")
            } catch { assert(!fm.fileExists(atPath: output.path)) }
        }
        // Reset cancellation must work without a timeout, including a process
        // ignoring SIGTERM. A fresh controller must allow the next solve.
        let cancellable = directory.appendingPathComponent("cancelled")
        try "#!/bin/sh\ntrap '' TERM\nprintf ready > ready.txt\nexec /bin/sleep 60\n".write(to: binary, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let control = SolverControl()
        DispatchQueue.global().async {
            for _ in 0..<500 {
                if fm.fileExists(atPath: cancellable.appendingPathComponent("ready.txt").path) { break }
                Thread.sleep(forTimeInterval: 0.01)
            }
            control.cancel()
        }
        let start = ProcessInfo.processInfo.systemUptime
        do {
            try runSolver(home: home, input: request, output: cancellable, control: control)
            fatalError("Cancelled result accepted")
        } catch { assert(error is SolverCancelled, String(describing: error)) }
        assert(ProcessInfo.processInfo.systemUptime - start < 8)
        try "#!/bin/sh\nprintf '%s' '{\"strategy\":{}}' > result.json\n".write(to: binary, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let next = directory.appendingPathComponent("after-reset")
        try runSolver(home: home, input: request, output: next, control: SolverControl())
        let preCancelled = SolverControl(); preCancelled.cancel()
        do {
            try runSolver(home: home, input: request, output: directory.appendingPathComponent("pre-cancelled"), control: preCancelled)
            fatalError("Pre-cancelled solve accepted")
        } catch { assert(error is SolverCancelled, String(describing: error)) }
        print("Cancellation passed: no-deadline wait, forced stop, pre-launch cancel and fresh-controller restart.")
        print("Storage budget passed: exact/legacy estimates, rounding, validation, typed failure, identical-request retry, environment and saved setup.")
    }
}
