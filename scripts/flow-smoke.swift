import Foundation

@main struct FlowSmoke {
    static func main() throws {
        let home = defaultSolver()!
        let root = home.appendingPathComponent("ranges/qb_ranges/100bb 2.5x 500rake")
        let pre = try Preflop(root: root)
        assert(pre.actor == "UTG")
        let opening = try pre.currentChart()!; assert(opening.actions.contains("Raise to 2.5bb"))
        try pre.advance("Raise to 2.5bb")
        assert(pre.actor == "MP")
        let response = try pre.currentChart()!; assert(response.actions.contains("Raise to 8.5bb"))
        try pre.advance("Fold"); assert(pre.actor == "CO")
        try pre.advance("Fold"); assert(pre.actor == "BTN")
        let btn = try pre.currentChart()!; assert(btn.actions.contains("Call"))
        try pre.advance("Call"); assert(pre.finished && pre.folded.count == 4)
        let handoff = try pre.handoff()
        assert(handoff.oopSeat == "UTG" && handoff.ipSeat == "BTN")
        assert(handoff.pot == 6.5 && handoff.stack == 97.5)
        let openingRange = try parseRange(String(contentsOf: root.appendingPathComponent("UTG/UTG_2.5bb.txt"), encoding: .utf8))
        assert(handoff.oopRange == openingRange)
        let carried = try handoff.input(flop: "Qs,8d,7h")
        assert(carried.oop == handoff.oopRange && carried.ip == handoff.ipRange)
        assert(carried.ipSeat == "BTN" && carried.oopSeat == "UTG")
        do { _ = try handoff.input(flop: "Qs,8d,7h,2c"); fatalError("Turn accepted as flop") } catch {}
        let blind = try Preflop(root: root)
        try blind.advance("Raise to 2.5bb")
        for _ in 0..<4 { try blind.advance("Fold") }
        try blind.advance("Call")
        let blindHandoff = try blind.handoff()
        assert(blindHandoff.oopSeat == "BB" && blindHandoff.ipSeat == "UTG")
        assert(blindHandoff.pot == 5.5 && blindHandoff.stack == 97.5)
        let folds = try Preflop(root: root)
        for _ in 0..<5 { _ = try folds.currentChart(); try folds.advance("Fold") }
        assert(folds.finished && folds.message.contains("BB wins"))
        let raised = try Preflop(root: root)
        try raised.advance("Raise to 2.5bb"); try raised.advance("Raise to 8.5bb")
        assert(raised.actor == "UTG"); _ = try raised.currentChart()
        try raised.advance("Call")
        let reraised = try raised.handoff()
        assert(reraised.pot == 18.5 && reraised.stack == 91.5)
        assert(reraised.oopRange != openingRange)
        let expectedReraiseRange = try parseRange(String(contentsOfFile: reraised.rangeSources["UTG"]!, encoding: .utf8))
        assert(reraised.oopRange == expectedReraiseRange)
        let input = try PostflopInput(board: "Qs,8d,7h,2c", pot: "4", stack: "10", ip: "T9s", oop: "JTs,43s")
        // Written for Sui by us: guard the interactive target and its progress label.
        assert(input.script().contains("set_accuracy 2\n"))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("sui-flow-" + UUID().uuidString)
        _ = try solvePostflop(input, home: home, output: output, timeout: 120)
        let post = try Postflop(input: input, output: output)
        assert(post.actor == "OOP")
        assert(post.actions == ["CHECK", "BET 4.000000", "BET 10.000000"])
        assert(post.label("BET 4.000000").hasPrefix("Bet pot"))
        assert(post.label("BET 10.000000").hasPrefix("All-in"))
        let namedInput = try PostflopInput(board: "Qs,8d,7h,2c", pot: "4", stack: "10", ip: "T9s", oop: "JTs,43s", ipSeat: "BTN", oopSeat: "UTG")
        let named = try Postflop(input: namedInput, output: output)
        assert(named.actor == "UTG")
        try named.advance("BET 4.000000"); assert(named.actor == "BTN")
        try named.advance("FOLD"); assert(named.ending?.contains("UTG wins") == true)
        let chart = try post.currentChart()!
        assert(abs(chart.frequencies["JTs"]!.reduce(0,+) - 1) < 0.001)
        assert(chart.frequencies["AA"]!.reduce(0,+) == 0)
        try post.advance("BET 4.000000")
        assert(post.actor == "IP" && post.pot == 8 && post.remaining == [10,6])
        try post.advance("RAISE 10.000000")
        assert(post.pot == 18 && post.actions == ["CALL", "FOLD"])
        try post.advance("CALL")
        assert(post.ending != nil && post.pot == 24 && post.remaining == [0,0])
        assert(!post.needsCard && post.nextCards.isEmpty)
        do { _ = try post.nextStreetInput("3s"); fatalError("Dealt after all-in") } catch {}
        var street = try Postflop(input: input, output: output)
        try street.advance("CHECK"); try street.advance("CHECK")
        assert(street.needsCard && !street.nextCards.contains("Qs"))
        street = try solvePostflop(street.nextStreetInput("3s"), home: home, output: output.appendingPathComponent("river"), timeout: 120)
        assert(street.board.count == 5 && street.actor == "OOP")
        _ = try street.currentChart()
        try street.advance("CHECK"); try street.advance("CHECK")
        assert(street.ending?.contains("showdown") == true)
        let called = try Postflop(input: input, output: output)
        try called.advance("BET 4.000000"); try called.advance("CALL")
        let continuation = try called.nextStreetInput("3s")
        assert(continuation.pot == 12 && continuation.stack == 6)
        assert(continuation.ip.keys.allSatisfy { $0.count == 4 && !comboCards($0).contains("3s") })
        assert(called.board.count == 4) // Preparing a solve does not mutate the previous street.
        let lowWeight = PostflopInput(board: input.board + ["3s"], pot: 4, stack: 10,
            ip: ["9cTc": 1, "9dTd": 0.0001], oop: ["JcQc": 1, "JhQh": 0.2], seats: ["BTN", "UTG"])
        let lowOutput = output.appendingPathComponent("low-weight")
        let low = try solvePostflop(lowWeight, home: home, output: lowOutput, timeout: 120)
        try low.advance("CHECK")
        assert(low.node.strategy!.strategy.keys.map(comboKey).contains("9dTd"))
        let folded = try Postflop(input: input, output: output)
        try folded.advance("BET 10.000000"); try folded.advance("FOLD")
        assert(folded.ending?.contains("OOP wins") == true)
        assert(!folded.needsCard && folded.nextCards.isEmpty)
        do { _ = try folded.nextStreetInput("3s"); fatalError("Dealt after fold") } catch {}
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("sui-shove-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        for name in ["UTG_100bb.txt", "UTG_100bb_MP_Call.txt"] {
            try "AA".write(to: fixture.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let shove = try Preflop(root: fixture)
        try shove.advance("Raise to 100bb"); try shove.advance("Call")
        assert(shove.finished && shove.allin == Set([0,1]) && shove.ending != nil)
        do { _ = try shove.handoff(); fatalError("Flop after preflop all-in") } catch {}
        try "Iter: 11\nTotal exploitability 1.25 precent\nIter: 21".write(to: fixture.appendingPathComponent("solver.log"), atomically: true, encoding: .utf8)
        assert(solverProgress(at: fixture).contains("Iteration 11 / 200"))
        assert(solverProgress(at: fixture).contains("1.250%"))
        // Written for Sui by us: the loading view must match the new solve target.
        assert(solverProgress(at: fixture).contains("target 2%"))
        do { _ = try PostflopInput(board: "As,As,2c", pot: "4", stack: "10", ip: "AA", oop: "KK"); fatalError("Duplicate board accepted") } catch {}
        if CommandLine.arguments.contains("--handoff") {
            // A narrow, low-SPR preflop fixture exercises the entire bridge without
            // running a large 100bb chart solve as a regression check.
            let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("sui-handoff-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
            try "T9s".write(to: fixture.appendingPathComponent("UTG_90.0bb.txt"), atomically: true, encoding: .utf8)
            try "JTs,43s".write(to: fixture.appendingPathComponent("UTG_90.0bb_BB_Call.txt"), atomically: true, encoding: .utf8)
            for seat in ["MP", "CO", "BTN", "SB"] {
                try "AA".write(to: fixture.appendingPathComponent("UTG_90.0bb_\(seat)_FOLD.txt"), atomically: true, encoding: .utf8)
            }
            let bridged = try Preflop(root: fixture)
            try bridged.advance("Raise to 90.0bb")
            for _ in 0..<4 { _ = try bridged.currentChart(); try bridged.advance("Fold") }
            try bridged.advance("Call")
            let bridge = try bridged.handoff()
            assert(bridge.pot == 180.5 && bridge.stack == 10 && bridge.oopSeat == "BB")
            let solved = try solvePostflop(bridge.input(flop: "Qs,8d,7h"), home: home, output: fixture.appendingPathComponent("solve"), timeout: 180)
            assert(solved.actor == "BB")
            _ = try solved.currentChart()
            try solved.advance("BET 10.000000"); assert(solved.actor == "UTG")
            try solved.advance("CALL")
            assert(solved.ending?.contains("All-in called") == true && solved.pot == 200.5)
            print("Preflop → carried ranges/pot/stacks → real flop solve → called all-in passed.")
        }
        if CommandLine.arguments.contains("--flop") {
            let flopInput = try PostflopInput(board: "Qs,8d,7h", pot: "4", stack: "10", ip: "T9s", oop: "JTs,43s")
            let flopOutput = FileManager.default.temporaryDirectory.appendingPathComponent("sui-flop-" + UUID().uuidString)
            var flop = try solvePostflop(flopInput, home: home, output: flopOutput, timeout: 180)
            try flop.advance("CHECK"); try flop.advance("CHECK"); assert(flop.needsCard)
            flop = try solvePostflop(flop.nextStreetInput("2c"), home: home, output: flopOutput.appendingPathComponent("turn"), timeout: 120); _ = try flop.currentChart()
            try flop.advance("CHECK"); try flop.advance("CHECK"); assert(flop.needsCard)
            flop = try solvePostflop(flop.nextStreetInput("3s"), home: home, output: flopOutput.appendingPathComponent("river"), timeout: 120); _ = try flop.currentChart()
            try flop.advance("CHECK"); try flop.advance("CHECK"); assert(flop.ending != nil)
            print("Real flop → turn → river → showdown passed. Artifacts: \(flopOutput.path)")
        }
        print("Flow smoke passed: UTG/raise/call/fold transitions, turn order, all-in accounting, next card, showdown, range averages.")
    }
}
