# Proxmox

A panel that shows one Proxmox host's overall CPU use and each guest's share of it. The CPU menu
opens it with **Proxmox…**, which appears once an address is set in Settings › Proxmox.

## Invariants

- **Nothing runs while the panel is closed.** `ProxmoxPanelView` drives `ProxmoxSession.poll()` from
  `.task`, so closing the window cancels the loop. There is no background timer and no menu bar
  readout.
- **The fetch follows the networked-feature rule.** `ProxmoxService` uses a private `.ephemeral`
  session with `urlCache = nil`, never `URLSession.shared`, so no reply reaches the disk.
- **The token secret lives only in the Keychain.** `KeychainSecretStore.proxmox` holds it. It is never
  in `UserDefaults` or settings.json.
- **A certificate pin is a trust grant, so settings.json never carries it.** Only the address and the
  token ID have `SettingsFileKey`s. `settings-file-test` checks that the fingerprint and the secret
  stay absent.
- **The math stays in `Model/`.** `ProxmoxFeed`, `ProxmoxConnection` and `ProxmoxFailure` import
  neither AppKit nor SwiftUI, so `Tests/proxmox-test.swift` compiles them directly.

## The request

One call, `GET /api2/json/cluster/resources`, returns the node and every guest. Perch reads the
first node and ignores storage and SDN entries. Templates are dropped. The header is
`Authorization: PVEAPIToken=<token ID>=<secret>`.

Proxmox's stats daemon updates these numbers about every ten seconds. The panel polls every five,
so a new value shows within one interval of the daemon's update.

## The numbers

- **Host CPU** is the node's `cpu`, a fraction of all its cores.
- **A guest's share** is `cpu × maxcpu ÷ host cores`. A guest's own `cpu` is a fraction of its
  allotted cores, so a 2-core VM at 100% would otherwise look as busy as the whole host.
- Running guests sort by share, then stopped guests by ID. Stopped guests draw at the same 60%
  opacity as the menu bar's efficiency cores.
- The bar colour is the menu bar meter's `LoadZone`: blue, orange from 60%, red from 80%.

## The address

`ProxmoxConnection.baseURL(from:)` turns what the user typed into a base URL:

| Typed | Base URL |
| --- | --- |
| `pve.tail1234.ts.net` | `https://pve.tail1234.ts.net:8006` |
| `100.64.0.7` | `https://100.64.0.7:8006` |
| `192.168.1.5:9000` | `https://192.168.1.5:9000` |
| `https://pve.example.com` | `https://pve.example.com` (port 443) |

A bare host gets `https` and port 8006. A typed `https://` keeps port 443, which suits a host behind
`tailscale serve` or a reverse proxy. A pasted web UI link loses its path and fragment. A plain
`http` address is refused, because App Transport Security would block it.

## The certificate

Proxmox installs a self-signed certificate, which macOS does not trust. `TrustDelegate` accepts a
certificate when either is true:

1. macOS trusts it (`SecTrustEvaluateWithError`), for example one from `tailscale cert`.
2. The SHA-256 of the leaf certificate equals the pinned fingerprint.

**Trust…** in Settings fetches the leaf certificate without sending the token. It shows the
fingerprint in a Perch dialog. The user compares it with the one under System › Certificates in the
Proxmox web UI, then confirms. When macOS already trusts the certificate, Perch clears any pin and
says so.

The pin skips the hostname check, because a self-signed certificate rarely names a Tailscale address.
The fingerprint match is the stronger check.

## App Transport Security

Inside an app bundle, App Transport Security (ATS) refuses a certificate that macOS does not trust,
even after `TrustDelegate` accepts it. Two kinds of address get past ATS:

- **A private LAN IP**, such as `192.168.0.230`. ATS exempts these by itself.
- **A `*.ts.net` name.** `Info.plist` has an ATS exception for `ts.net` and its subdomains.

A Tailscale `100.x` IP is neither, so ATS blocks it and the panel shows `certificateBlocked`. A host
with a certificate macOS trusts works at any address.

## Setting up a token

1. In the Proxmox web UI, open Datacenter › Permissions › API Tokens.
2. Add a token, for example `root@pam!perch`. Keep "Privilege Separation" on.
3. Copy the secret. Proxmox shows it only once.
4. In Datacenter › Permissions, add an API Token Permission: path `/`, the new token, role
   `PVEAuditor`.

`PVEAuditor` is read-only. A 403 from the host means the token has no role on `/`.
