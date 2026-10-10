import SwiftUI

/// The host's overall CPU, then each guest's share of it; stopped guests sit dimmed at the end.
struct ProxmoxPanelView: View {
    let session: ProxmoxSession

    var body: some View {
        Group {
            switch session.phase {
            case .loading: ProgressView()
            case .loaded(let snapshot): ProxmoxSnapshotView(snapshot: snapshot)
            case .failed(let failure): ProxmoxFailureView(failure: failure)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await session.poll() }
    }
}

private struct ProxmoxSnapshotView: View {
    let snapshot: ProxmoxSnapshot

    var body: some View {
        Form {
            Section {
                SettingsRow(title: "Host CPU", subtitle: hostSubtitle) {
                    ProxmoxLoadReading(load: snapshot.hostLoad)
                }
                .accessibilityElement(children: .combine)
            }
            Section("Guests") {
                if snapshot.guests.isEmpty {
                    Text("No guests on this node").foregroundStyle(.secondary)
                }
                ForEach(snapshot.guests) { guest in
                    ProxmoxGuestRow(guest: guest)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var hostSubtitle: String {
        "\(snapshot.node) · \(snapshot.coreCount) \(snapshot.coreCount == 1 ? "core" : "cores")"
    }
}

private struct ProxmoxGuestRow: View {
    /// Matches the menu bar meter's efficiency cores, the app's one other "present but quiet" look.
    private static let stoppedOpacity = MeterImage.efficiencyAlpha

    let guest: ProxmoxGuest

    var body: some View {
        SettingsRow(
            title: guest.name, subtitle: subtitle,
            labelOpacity: guest.isRunning ? 1 : Self.stoppedOpacity
        ) {
            Image(systemName: guest.kind == .virtualMachine ? "desktopcomputer" : "shippingbox")
                .foregroundStyle(.secondary)
                .frame(width: SettingsListMetrics.iconSize)
        } trailing: {
            if guest.isRunning {
                ProxmoxLoadReading(load: guest.hostShare)
            } else {
                Text("Stopped")
                    .foregroundStyle(.secondary)
                    .opacity(Self.stoppedOpacity)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        "\(guest.kind == .virtualMachine ? "VM" : "Container") \(guest.id)"
    }
}

/// A bar coloured like the menu bar meter, then the percentage in a fixed column.
private struct ProxmoxLoadReading: View {
    let load: Double

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ProgressView(value: load)
                .progressViewStyle(.linear)
                .tint(Color(nsColor: MeterImage.color(for: LoadZone(load: load))))
                .frame(width: Theme.Size.proxmoxLoadBar)
                .accessibilityHidden(true)
            Text(load, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
                .frame(width: Theme.Size.proxmoxPercentColumn, alignment: .trailing)
        }
    }
}

private struct ProxmoxFailureView: View {
    @Environment(AppCore.self) private var core
    let failure: ProxmoxFailure

    var body: some View {
        ContentUnavailableView {
            Label("Cannot read Proxmox", systemImage: "exclamationmark.triangle")
        } description: {
            Text(failure.message)
        } actions: {
            Button("Open Settings") { core.proxmoxCoordinator.showSettings() }
        }
    }
}
