import Foundation

/// How long a project must sit unchanged before the list shows it.
enum CleanupAge: String, CaseIterable, Identifiable, Sendable {
    case any, oneMonth, threeMonths, sixMonths, oneYear

    var id: Self { self }

    var title: String {
        switch self {
        case .any: "Any Time"
        case .oneMonth: "1 Month"
        case .threeMonths: "3 Months"
        case .sixMonths: "6 Months"
        case .oneYear: "1 Year"
        }
    }

    private var months: Int {
        switch self {
        case .any: 0
        case .oneMonth: 1
        case .threeMonths: 3
        case .sixMonths: 6
        case .oneYear: 12
        }
    }

    /// Projects unchanged since the cutoff, the most space first.
    func projects(in report: CleanupReport, now: Date, calendar: Calendar) -> [CleanupProject] {
        let cutoff = calendar.date(byAdding: .month, value: -months, to: now) ?? now
        return report.projects
            .filter { self == .any || $0.lastModified < cutoff }
            .sorted { ($0.reclaimable, $1.path) > ($1.reclaimable, $0.path) }
    }
}
