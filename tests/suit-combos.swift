import Foundation

@main struct SuitComboChecks {
    static func main() throws {
        var allKeys = Set<String>()
        for hand in hands {
            let combos = suitCombinations(hand)
            assert(combos.count == Int(combinationCount(hand)))
            assert(Set(combos.map { $0.sorted().joined() }).count == combos.count)
            for combo in combos {
                assert(combo[0] != combo[1])
                let classified = try comboHand(combo.joined())
                assert(classified == hand)
                allKeys.insert(combo.sorted().joined())
            }
        }
        assert(allKeys.count == 1326)
        let offsuit = suitCombinations("AKo")
        assert(offsuit.count == 12)
        for row in 0..<4 {
            let cells = Array(offsuit[(row * 3)..<(row * 3 + 3)])
            assert(Set(cells.map { String($0[0].suffix(1)) }).count == 1)
            assert(cells.allSatisfy { $0[0].suffix(1) != $0[1].suffix(1) })
        }
        let spot = Spot(id: "fixture", position: "IP", actions: [])
        var chart = Chart(source: "fixture", spot: spot, note: "", actions: ["Call", "Fold"], frequencies: ["AKs": [0.4, 0.6], "AA": [0.7, 0.3], "AKo": [0, 0]])
        assert(chart.combinations(for: "AKs").allSatisfy { !$0.exact && $0.frequencies == [0.4, 0.6] })
        assert(chart.combinations(for: "AA").count == 6)
        assert(chart.combinations(for: "AKo").allSatisfy { $0.status == .outsideRange })
        chart.board = ["As"]
        chart.comboReach = ["AsKs": 1, "AhKh": 1, "AdKd": 0.25, "AcKc": 0]
        chart.comboFrequencies = ["AsKs": [0.5, 0.5], "AhKh": [1, 0], "AdKd": [0, 1], "AcKc": [0.2, 0.8]]
        var cells = chart.combinations(for: "AKs")
        assert(cells.map { $0.status } == [.blocked, .available, .available, .outsideRange])
        assert(cells[1].frequencies == [1, 0] && cells[2].frequencies == [0, 1])
        assert(cells[1].summary(actions: chart.actions).contains("Call: 100.0%"))
        chart.comboFrequencies?.removeValue(forKey: "AdKd")
        cells = chart.combinations(for: "AKs")
        assert(cells[2].status == .unavailable && cells[2].frequencies.isEmpty)

        // Read real Postflop models from an asymmetric exact-combo fixture.
        let fm = FileManager.default
        let output = fm.temporaryDirectory.appendingPathComponent("sui-suit-fixture-" + UUID().uuidString)
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: output) }
        let vectors: [String: [Double]] = ["AsKs": [0.9, 0.1], "KhAh": [0.1, 0.9], "AdKd": [0.3, 0.7], "AcKc": [0.4, 0.6], "AsKd": [1, 0], "KsAd": [0, 1]]
        let node: [String: Any] = ["node_type": "action_node", "player": 0, "actions": ["CHECK", "BET 2.000000"],
            "strategy": ["actions": ["CHECK", "BET 2.000000"], "strategy": vectors],
            "childrens": ["CHECK": ["node_type": "action_node", "player": 1, "actions": ["CHECK"],
                "strategy": ["actions": ["CHECK"], "strategy": ["JhTh": [1.0]]],
                "childrens": ["CHECK": ["node_type": "chance_node"]]]]]
        try JSONSerialization.data(withJSONObject: node).write(to: output.appendingPathComponent("result.json"))
        let input = try PostflopInput(board: "Ah,8d,7h", pot: "6.5", stack: "20.5", ip: "AKs,AKo", oop: "JTs")
        let hand = try Postflop(input: input, output: output)
        let first = try hand.currentChart()!
        var frame = node
        frame.removeValue(forKey: "childrens")
        frame["iteration"] = 1
        try JSONSerialization.data(withJSONObject: frame).write(to: output.appendingPathComponent("preview.json"))
        let preview = try Postflop(input: input, output: output, preview: true).currentChart()!
        assert(preview.actions == first.actions && preview.frequencies == first.frequencies)
        assert(preview.comboFrequencies == first.comboFrequencies)

        let suited = first.combinations(for: "AKs")
        assert(suited.map { $0.status } == [.available, .blocked, .available, .available])
        assert(suited[0].frequencies == [0.9, 0.1])
        assert(suited[2].frequencies == [0.3, 0.7])
        assert(abs(first.frequencies["AKs"]![0] - (0.9 + 0.3 + 0.4) / 3) < 1e-12)
        assert(first.combinations(for: "AKo").first { $0.key == "AdKs" }!.frequencies == [0, 1])
        try hand.advance("CHECK"); try hand.advance("CHECK")
        let nextInput = try hand.nextStreetInput("2c")
        let next = try Postflop(input: nextInput, output: output)
        let nextChart = try next.currentChart()!
        assert(nextChart.combinations(for: "AKo").first { $0.key == "AdKs" }!.status == .outsideRange)
        assert(nextChart.combinations(for: "AKo").first { $0.key == "AsKd" }!.frequencies == [1, 0])
        let history = StreetSolveHistory()
        let flopDirectory = output.appendingPathComponent("cached-flop")
        let turnDirectory = output.appendingPathComponent("cached-turn")
        let alternateDirectory = output.appendingPathComponent("alternate-turn")
        let importedDirectory = output.appendingPathComponent("imported-river")
        for directory in [flopDirectory, turnDirectory, alternateDirectory, importedDirectory] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: directory.appendingPathComponent("result.json"))
        }
        history.remember(input, output: flopDirectory, owned: true)
        history.remember(nextInput, output: turnDirectory, owned: true)
        history.remember(input, output: flopDirectory, owned: true, preservingLater: true)
        assert(history.entries[4]?.output == turnDirectory)
        var alternate = nextInput; alternate.betSizes = [.quarter]
        history.remember(alternate, output: alternateDirectory, owned: true)
        assert(history.matching(nextInput)?.output == turnDirectory)
        assert(fm.fileExists(atPath: turnDirectory.path))
        var budgetOnly = input; budgetOnly.storageBudgetGiB += 1
        assert(history.matching(budgetOnly)?.output == flopDirectory)
        let riverInput = PostflopInput(board: nextInput.board + ["3c"], pot: nextInput.pot, stack: nextInput.stack, ip: nextInput.ip, oop: nextInput.oop, seats: [nextInput.ipSeat, nextInput.oopSeat])
        history.remember(riverInput, output: importedDirectory, owned: false)
        history.discardDifferentFlop(input)
        assert(fm.fileExists(atPath: flopDirectory.path) && history.entries.count == 3)
        let differentFlop = try PostflopInput(board: "As,8d,7h", pot: "6.5", stack: "20.5", ip: "AKs,AKo", oop: "JTs")
        history.discardDifferentFlop(differentFlop)
        assert(history.entries.isEmpty && history.matching(nextInput) == nil)
        assert(!fm.fileExists(atPath: flopDirectory.path) && !fm.fileExists(atPath: turnDirectory.path) && !fm.fileExists(atPath: alternateDirectory.path))
        assert(fm.fileExists(atPath: importedDirectory.path))
        let control = SolverControl()
        try control.finish() // User may click before the background process starts.
        let stopFile = output.appendingPathComponent("stop-request")
        try control.attachStopFile(stopFile)
        assert(fm.fileExists(atPath: stopFile.path) && !control.isCancelled)
        control.cancel(); assert(control.isCancelled)
        try "Iter: 0\nTotal exploitability 5 precent\nSUI_ITERATION: 7\nIter: 11\n".write(to: output.appendingPathComponent("solver.log"), atomically: true, encoding: .utf8)
        let progress = solverProgress(at: output)
        assert(progress.contains("Iteration 7 / 200") && progress.contains("5.000%") && progress.contains("(iteration 0)"))
        print("Suit combinations passed: 1326 unique hands, 3x4 offsuit layout, pair/suited counts, exact suit strategies, blockers, missing data, reach conditioning and class averages.")
    }
}
