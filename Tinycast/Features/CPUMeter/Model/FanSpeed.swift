import Foundation

/// One fan as the SMC reports it, in revolutions per minute.
struct FanReading: Equatable, Sendable {
    let rpm: Double
    let maximum: Double

    /// Apple silicon stops an idle fan outright, so a reading this low is a stopped fan, not a slow one.
    static let stoppedBelow: Double = 100

    var isSpinning: Bool { rpm >= Self.stoppedBelow }

    /// The share of the fan's top speed, as "35" for 35%.
    var percent: Int {
        guard maximum > 0 else { return 0 }
        return Int((min(rpm / maximum, 1) * 100).rounded())
    }

    var speedText: String {
        isSpinning ? "\(Int(rpm.rounded()).formatted()) rpm · \(percent)%" : "Off"
    }

    static func name(index: Int, count: Int) -> String {
        count == 1 ? "Fan" : "Fan \(index + 1)"
    }
}

/// Decodes the SMC's raw key bytes by the four-character type the SMC gives with them.
enum SMCValue {
    static func decode(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt " where bytes.count >= 4:
            // Apple silicon writes its floats little-endian.
            let bits = bytes.prefix(4).reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            return Double(Float(bitPattern: bits))
        case "fpe2" where bytes.count >= 2:
            // Intel's unsigned fixed point: big-endian, two fraction bits.
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "ui8 " where !bytes.isEmpty:
            return Double(bytes[0])
        default:
            return nil
        }
    }
}
