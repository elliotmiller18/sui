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
        print("Suit combinations passed: 1326 unique hands, 3x4 offsuit layout, pair/suited counts, exact suit strategies, blockers, missing data, reach conditioning and class averages.")
    }
}
