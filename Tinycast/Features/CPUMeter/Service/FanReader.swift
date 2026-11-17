import Foundation
import IOKit

/// Reads each fan's speed from the AppleSMC driver, which answers an unprivileged reader.
enum FanReader {
    /// Each read is one kernel call of about a tenth of a millisecond, so a menu can read on open.
    nonisolated static func read() -> [FanReading] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return [] }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            return []
        }
        defer { IOServiceClose(connection) }
        // A Mac with no fan, such as a MacBook Air, has no FNum key.
        let count = Int(value(of: "FNum", on: connection) ?? 0)
        return (0..<count).compactMap { index in
            guard let rpm = value(of: "F\(index)Ac", on: connection),
                let maximum = value(of: "F\(index)Mx", on: connection)
            else { return nil }
            return FanReading(rpm: rpm, maximum: maximum)
        }
    }

    private nonisolated static func value(of key: String, on connection: io_connect_t) -> Double? {
        let code = key.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        var infoRequest = SMCParamStruct()
        infoRequest.key = code
        infoRequest.command = SMCParamStruct.readKeyInfo
        guard let info = call(&infoRequest, on: connection) else { return nil }
        var readRequest = SMCParamStruct()
        readRequest.key = code
        readRequest.keyInfo = info.keyInfo
        readRequest.command = SMCParamStruct.readBytes
        guard let reply = call(&readRequest, on: connection) else { return nil }
        let typeBytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: info.keyInfo.dataType >> $0) }
        guard let type = String(bytes: typeBytes, encoding: .ascii) else { return nil }
        let bytes = withUnsafeBytes(of: reply.bytes) { Array($0.prefix(Int(info.keyInfo.dataSize))) }
        return SMCValue.decode(type: type, bytes: bytes)
    }

    private nonisolated static func call(
        _ input: inout SMCParamStruct, on connection: io_connect_t
    ) -> SMCParamStruct? {
        var output = SMCParamStruct()
        var size = MemoryLayout<SMCParamStruct>.stride
        let status = IOConnectCallStructMethod(
            connection, SMCParamStruct.handleYPCEvent, &input, MemoryLayout<SMCParamStruct>.stride,
            &output, &size)
        return status == kIOReturnSuccess && output.result == 0 ? output : nil
    }
}

/// The driver's 80-byte `SMCParamStruct`; field order and padding must match the C layout exactly.
private struct SMCParamStruct {
    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var attributes: UInt8 = 0
        // C pads this struct to 12 bytes; Swift would start the next field at byte 9 without it.
        var padding: (UInt8, UInt8, UInt8) = (0, 0, 0)
    }

    static let handleYPCEvent: UInt32 = 2
    static let readBytes: UInt8 = 5
    static let readKeyInfo: UInt8 = 9

    var key: UInt32 = 0
    var version: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
    var limitData: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
    var keyInfo = KeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var command: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
}
