import Foundation

/// One process's cumulative CPU time, in the same units as the clock that timed the sample.
struct ProcessSample: Equatable, Sendable {
    let pid: Int32
    let cpuTime: UInt64
}

/// One process's CPU use over the last interval; 100 is one core busy the whole time.
struct ProcessUsage: Equatable, Sendable {
    let pid: Int32
    let percent: Double
}

enum ProcessLoad {
    /// A process with no earlier sample has no interval to measure yet, so it waits a tick.
    static func top(
        previous: [Int32: UInt64], current: [ProcessSample], elapsed: UInt64, limit: Int
    ) -> [ProcessUsage] {
        guard elapsed > 0 else { return [] }
        let usages = current.compactMap { sample -> ProcessUsage? in
            // A reused pid can start below its predecessor's total; that is not a measurement.
            guard let earlier = previous[sample.pid], sample.cpuTime >= earlier else { return nil }
            let percent = Double(sample.cpuTime - earlier) / Double(elapsed) * 100
            return ProcessUsage(pid: sample.pid, percent: percent)
        }
        let ranked = usages.sorted {
            $0.percent != $1.percent ? $0.percent > $1.percent : $0.pid < $1.pid
        }
        return Array(ranked.prefix(limit))
    }
}
