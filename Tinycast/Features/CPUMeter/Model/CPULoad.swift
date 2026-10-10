import Foundation

/// One core's cumulative tick counters, as `host_processor_info` reports them.
struct CoreTicks: Equatable, Sendable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32
}

/// One core's share of the last interval, each part between 0 and 1.
struct CoreLoad: Equatable, Sendable {
    var user: Double
    var system: Double

    static let idle = CoreLoad(user: 0, system: 0)

    var total: Double { user + system }
    var zone: LoadZone { LoadZone(load: total) }
}

/// How busy a core is, for the colour its bar takes; the cuts are the ones Stats draws with.
enum LoadZone: Equatable, Sendable {
    case low, high, saturated

    init(load: Double) {
        switch load {
        case ..<0.6: self = .low
        case ..<0.8: self = .high
        default: self = .saturated
        }
    }
}

enum CPULoad {
    /// Counters wrap at `UInt32.max`, so each delta is a wrapping subtraction.
    static func loads(previous: [CoreTicks], current: [CoreTicks]) -> [CoreLoad] {
        guard previous.count == current.count else { return current.map { _ in .idle } }
        return zip(previous, current).map { old, new in
            // Nice time is user time at a lower priority, so it counts as user.
            let user = Double(new.user &- old.user) + Double(new.nice &- old.nice)
            let system = Double(new.system &- old.system)
            let idle = Double(new.idle &- old.idle)
            let total = user + system + idle
            guard total > 0 else { return .idle }
            return CoreLoad(user: user / total, system: system / total)
        }
    }
}
