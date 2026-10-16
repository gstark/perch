import Charts
import SwiftUI

/// The startup disk over a chosen range, drawn as free space, used space or change per interval.
struct DiskHistoryPanelView: View {
    @Environment(AppCore.self) private var core
    @State private var range: DiskHistoryRange = .week
    @State private var kind: DiskChartKind = .free

    var body: some View {
        let coordinator = core.diskHistoryCoordinator
        let samples = coordinator.store.samples
        let points = DiskHistory.points(samples, over: range, now: .now)
        Form {
            Section {
                SettingsRow(title: title(coordinator.current), subtitle: subtitle(samples)) {
                    Button("Show File") { coordinator.revealFile() }
                }
            }
            Section {
                Picker("Range", selection: $range) {
                    ForEach(DiskHistoryRange.allCases) { Text($0.title).tag($0) }
                }
                Picker("Show", selection: $kind) {
                    ForEach(DiskChartKind.allCases) { Text($0.title).tag($0) }
                }
                if points.count < 2 {
                    Text("A chart appears once this range holds two hourly samples.")
                        .foregroundStyle(.secondary)
                } else {
                    DiskHistoryChart(points: points, kind: kind)
                        .frame(height: Theme.Size.diskHistoryChart)
                }
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
    }

    private func title(_ current: DiskSample?) -> String {
        guard let current else { return "Reading the disk…" }
        return "\(DiskBytes.text(current.available)) free of \(DiskBytes.text(current.total))"
    }

    private func subtitle(_ samples: [DiskSample]) -> String {
        guard let first = samples.first else { return "Records the startup disk once an hour." }
        let since = first.date.formatted(date: .abbreviated, time: .omitted)
        return "\(samples.count) hourly samples since \(since)"
    }
}

enum DiskChartKind: String, CaseIterable, Identifiable {
    case free, used, change

    var id: Self { self }

    var title: String {
        switch self {
        case .free: "Free"
        case .used: "Used"
        case .change: "Change"
        }
    }
}

struct DiskHistoryChart: View {
    let points: [DiskSample]
    let kind: DiskChartKind

    var body: some View {
        switch kind {
        case .free:
            Chart(points, id: \.date) { point in
                LineMark(x: .value("Time", point.date), y: .value("Free", Double(point.available)))
                    .foregroundStyle(.blue)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .byteAxis()
        case .used:
            Chart {
                ForEach(points, id: \.date) { point in
                    AreaMark(x: .value("Time", point.date), y: .value("Used", Double(point.used)))
                        .foregroundStyle(.blue.opacity(0.5))
                }
                if let total = points.last?.total {
                    RuleMark(y: .value("Capacity", Double(total)))
                        .lineStyle(StrokeStyle(dash: [4, 4]))
                        .foregroundStyle(.secondary)
                }
            }
            .byteAxis()
        case .change:
            Chart(DiskHistory.changes(points), id: \.end) { change in
                RectangleMark(
                    xStart: .value("From", change.start), xEnd: .value("To", change.end),
                    yStart: .value("Base", 0), yEnd: .value("Change", Double(change.bytes)))
                    .foregroundStyle(change.bytes > 0 ? .orange : .green)
            }
            .byteAxis()
        }
    }
}

enum DiskBytes {
    static func text(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    /// "3.2 GB used" or "1.1 GB freed", for a change in used space.
    static func change(_ bytes: Int64) -> String {
        bytes >= 0 ? "\(text(bytes)) used" : "\(text(-bytes)) freed"
    }
}

extension View {
    fileprivate func byteAxis() -> some View {
        chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let bytes = value.as(Double.self) {
                        Text(DiskBytes.text(Int64(bytes)))
                    }
                }
            }
        }
    }
}
