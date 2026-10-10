import Foundation

/// The Proxmox reply parsing, the per-guest host share, and how an address becomes a base URL.
@main
@MainActor
struct ProxmoxTests {
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
        snapshot()
        failureCases()
        addresses()
        fingerprints()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func snapshot() {
        let reply = """
            {"data":[
              {"type":"node","node":"pve","cpu":0.25,"maxcpu":8,"status":"online"},
              {"type":"storage","node":"pve","storage":"local"},
              {"type":"qemu","node":"pve","vmid":101,"name":"web","status":"running","cpu":0.5,"maxcpu":4},
              {"type":"lxc","node":"pve","vmid":200,"name":"dns","status":"running","cpu":1.0,"maxcpu":1},
              {"type":"qemu","node":"pve","vmid":100,"name":"old","status":"stopped","cpu":0,"maxcpu":2},
              {"type":"qemu","node":"pve","vmid":9000,"name":"tmpl","status":"stopped","template":1,"maxcpu":2},
              {"type":"lxc","node":"pve","vmid":300,"status":"running","cpu":2.0,"maxcpu":4}
            ]}
            """
        guard let snapshot = try? ProxmoxFeed.snapshot(resources: Data(reply.utf8)) else {
            expect(false, "a well-formed reply parses")
            return
        }
        expect(snapshot.node == "pve" && snapshot.coreCount == 8, "the node and its cores are read")
        expect(close(snapshot.hostLoad, 0.25), "the host load is the node's own cpu")
        expect(
            snapshot.guests.map(\.id) == [300, 101, 200, 100],
            "running guests by share, stopped last, templates and storage dropped")
        let web = snapshot.guests.first { $0.id == 101 }
        expect(web.map { close($0.hostShare, 0.25) } == true, "a guest's share scales by its cores")
        let dns = snapshot.guests.first { $0.id == 200 }
        expect(dns.map { close($0.hostShare, 0.125) } == true, "one busy core of eight is 12.5%")
        let unnamed = snapshot.guests.first { $0.id == 300 }
        expect(unnamed?.name == "300", "a guest with no name shows its ID")
        expect(unnamed.map { close($0.hostShare, 1) } == true, "a share never passes the host")
        let old = snapshot.guests.first { $0.id == 100 }
        expect(old?.isRunning == false && old?.hostShare == 0, "a stopped guest has no share")
        expect(old?.kind == .virtualMachine && dns?.kind == .container, "the guest kind is read")
    }

    static func failureCases() {
        expect(parseFailure("not json") == .malformedReply, "garbage is a malformed reply")
        expect(parseFailure(#"{"data":[]}"#) == .noNode, "a reply with no node says so")
        expect(ProxmoxFailure(httpStatus: 401) == .tokenRefused, "401 is a refused token")
        expect(ProxmoxFailure(httpStatus: 403) == .tokenLacksAccess, "403 is a missing role")
        expect(ProxmoxFailure(httpStatus: 500) == .httpStatus(500), "other codes pass through")
    }

    static func parseFailure(_ body: String) -> ProxmoxFailure? {
        do {
            _ = try ProxmoxFeed.snapshot(resources: Data(body.utf8))
            return nil
        } catch {
            return error
        }
    }

    static func addresses() {
        func base(_ address: String) -> String? {
            ProxmoxConnection.baseURL(from: address)?.absoluteString
        }
        expect(base("pve.tail1234.ts.net") == "https://pve.tail1234.ts.net:8006", "a bare host")
        expect(base("  100.64.0.7 ") == "https://100.64.0.7:8006", "a trimmed Tailscale IP")
        expect(base("192.168.1.5:9000") == "https://192.168.1.5:9000", "a bare host keeps its port")
        expect(base("https://pve.example.com") == "https://pve.example.com", "a scheme keeps 443")
        expect(
            base("https://pve:8006/#v1:0:18") == "https://pve:8006",
            "a pasted web UI link loses its path")
        expect(base("") == nil && base("http://pve") == nil, "empty or plain HTTP is refused")
        let connection = ProxmoxConnection(
            baseURL: URL(string: "https://pve:8006")!, tokenID: "root@pam!perch", secret: "s3cret",
            pinnedFingerprint: nil)
        expect(
            connection.resourcesURL.absoluteString == "https://pve:8006/api2/json/cluster/resources",
            "the resources path joins the base")
        expect(connection.authorization == "PVEAPIToken=root@pam!perch=s3cret", "the token header")
    }

    static func fingerprints() {
        let fingerprint = ProxmoxConnection.fingerprint(of: Data("abc".utf8))
        expect(
            fingerprint.hasPrefix("BA:78:16:BF:8F:01:CF:EA") && fingerprint.count == 32 * 3 - 1,
            "SHA-256 as colon-separated uppercase hex")
    }
}
