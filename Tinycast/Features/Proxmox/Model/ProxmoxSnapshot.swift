import Foundation

/// One VM or container, with its CPU stated as a share of the whole host.
struct ProxmoxGuest: Equatable, Sendable, Identifiable {
    enum Kind: String, Sendable {
        case virtualMachine = "qemu"
        case container = "lxc"
    }

    let id: Int
    let name: String
    let kind: Kind
    let isRunning: Bool
    /// 0...1 of every host core, not of the guest's own allotment.
    let hostShare: Double
}

/// The host's overall CPU and its guests: running by share, then stopped by ID.
struct ProxmoxSnapshot: Equatable, Sendable {
    let node: String
    let hostLoad: Double
    let coreCount: Int
    let guests: [ProxmoxGuest]
}

enum ProxmoxFeed {
    /// Reads `GET /cluster/resources`, which lists the node and every guest in one reply.
    static func snapshot(resources: Data) throws(ProxmoxFailure) -> ProxmoxSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: resources) else {
            throw .malformedReply
        }
        let host = reply.data.filter { $0.type == "node" }.min { $0.node ?? "" < $1.node ?? "" }
        guard let host, let node = host.node, let cores = host.maxcpu, cores > 0 else {
            throw .noNode
        }
        let guests = reply.data.compactMap { guest(from: $0, node: node, hostCores: cores) }
        return ProxmoxSnapshot(
            node: node, hostLoad: clamped(host.cpu ?? 0), coreCount: Int(cores),
            guests: guests.sorted(by: displayOrder))
    }

    private static func guest(from entry: Resource, node: String, hostCores: Double)
        -> ProxmoxGuest?
    {
        guard entry.node == node, entry.template != 1, let vmid = entry.vmid,
            let kind = entry.type.flatMap(ProxmoxGuest.Kind.init)
        else { return nil }
        let isRunning = entry.status == "running"
        // A guest's `cpu` is a fraction of its own `maxcpu` cores, not of the host's.
        let share = isRunning ? (entry.cpu ?? 0) * (entry.maxcpu ?? 0) / hostCores : 0
        return ProxmoxGuest(
            id: vmid, name: entry.name ?? "\(vmid)", kind: kind, isRunning: isRunning,
            hostShare: clamped(share))
    }

    private static func displayOrder(_ lhs: ProxmoxGuest, _ rhs: ProxmoxGuest) -> Bool {
        if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
        if lhs.hostShare != rhs.hostShare { return lhs.hostShare > rhs.hostShare }
        return lhs.id < rhs.id
    }

    private static func clamped(_ value: Double) -> Double { min(max(value, 0), 1) }

    private struct Reply: Decodable {
        let data: [Resource]
    }

    private struct Resource: Decodable {
        let type: String?
        let node: String?
        let vmid: Int?
        let name: String?
        let status: String?
        let cpu: Double?
        let maxcpu: Double?
        let template: Int?
    }
}
