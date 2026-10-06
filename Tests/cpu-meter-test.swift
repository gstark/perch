import Foundation

/// The meter's math: per-core shares, per-process percentages, and where each cell is drawn.
@main
@MainActor
struct CPUMeterTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    static func main() {
        coreLoads()
        processLoads()
        layout()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func coreLoads() {
        let before = [
            CoreTicks(user: 100, system: 50, idle: 850, nice: 0),
            CoreTicks(user: 0, system: 0, idle: 0, nice: 0)
        ]
        let after = [
            CoreTicks(user: 160, system: 70, idle: 870, nice: 0),
            CoreTicks(user: 0, system: 0, idle: 0, nice: 0)
        ]
        let loads = CPULoad.loads(previous: before, current: after)
        expect(close(loads[0].user, 0.6) && close(loads[0].system, 0.2), "shares divide by the interval's total ticks")
        expect(loads[1] == .idle, "a core with no ticks in the interval reads idle, not NaN")

        let niced = CPULoad.loads(
            previous: [CoreTicks(user: 0, system: 0, idle: 0, nice: 0)],
            current: [CoreTicks(user: 10, system: 0, idle: 70, nice: 20)])
        expect(close(niced[0].user, 0.3), "nice time counts as user time")

        let wrapped = CPULoad.loads(
            previous: [CoreTicks(user: UInt32.max - 9, system: 0, idle: 0, nice: 0)],
            current: [CoreTicks(user: 10, system: 0, idle: 20, nice: 0)])
        expect(close(wrapped[0].user, 0.5), "a counter that wraps still yields its true delta")

        let resized = CPULoad.loads(previous: [], current: after)
        expect(resized == [.idle, .idle], "a changed core count reads idle until the next interval")
    }

    static func processLoads() {
        let previous: [Int32: UInt64] = [1: 100, 2: 500, 3: 900]
        let current = [
            ProcessSample(pid: 1, cpuTime: 600),
            ProcessSample(pid: 2, cpuTime: 1_500),
            ProcessSample(pid: 3, cpuTime: 100),
            ProcessSample(pid: 4, cpuTime: 9_999)
        ]
        let top = ProcessLoad.top(previous: previous, current: current, elapsed: 1_000, limit: 10)
        expect(top.map(\.pid) == [2, 1], "busiest first; new and reused pids wait for a baseline")
        expect(close(top[0].percent, 100) && close(top[1].percent, 50), "100 is one core for the whole interval")

        let limited = ProcessLoad.top(previous: previous, current: current, elapsed: 1_000, limit: 1)
        expect(limited.map(\.pid) == [2], "the list stops at its limit")

        let tied = ProcessLoad.top(
            previous: [7: 0, 5: 0],
            current: [ProcessSample(pid: 7, cpuTime: 10), ProcessSample(pid: 5, cpuTime: 10)],
            elapsed: 100, limit: 10)
        expect(tied.map(\.pid) == [5, 7], "a tie orders by pid, so rows do not swap places each tick")

        expect(
            ProcessLoad.top(previous: previous, current: current, elapsed: 0, limit: 10).isEmpty,
            "no elapsed time measures nothing")
    }

    static func layout() {
        let twelve = MeterLayout(coreCount: 12)
        expect(twelve.columns == 6, "twelve cores make six columns of two")
        expect(MeterLayout(coreCount: 7).columns == 4, "an odd count rounds up to a last half column")
        expect(twelve.cell(for: 0).minY == 0 && twelve.cell(for: 1).minY > twelve.cell(for: 0).maxY, "core 1 sits under core 0")
        expect(twelve.cell(for: 2).minX > twelve.cell(for: 0).maxX, "core 2 starts the next column")
        expect(twelve.cell(for: 11).maxX == twelve.size.width, "the last column ends at the image's edge")
        expect(twelve.cell(for: 1).maxY == twelve.size.height, "the bottom row ends at the image's edge")
    }
}
