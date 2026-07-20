import Foundation

/// Completed sessions rolled up per calendar day. Only a work phase
/// or a plain countdown that ran to zero lands here; stops and skips
/// never count.
@MainActor
final class FocusStatsStore: ObservableObject {
    struct DayTotal: Codable, Equatable {
        var day: Date
        var minutes: Int
        var sessions: Int
    }

    /// Newest day first. A quarter of history is plenty.
    @Published private(set) var days: [DayTotal] = [] {
        didSet { save() }
    }

    private let storageKey = "moai.focusStats"
    private let maxDays = 90
    private let calendar = Calendar.current

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([DayTotal].self, from: data) {
            days = decoded
        }
    }

    func recordSession(minutes: Int) {
        guard minutes > 0 else { return }
        let today = calendar.startOfDay(for: Date())
        if let index = days.firstIndex(where: { calendar.isDate($0.day, inSameDayAs: today) }) {
            days[index].minutes += minutes
            days[index].sessions += 1
        } else {
            days.insert(DayTotal(day: today, minutes: minutes, sessions: 1), at: 0)
            if days.count > maxDays {
                days.removeLast(days.count - maxDays)
            }
        }
    }

    var todayMinutes: Int { todayTotal?.minutes ?? 0 }
    var todaySessions: Int { todayTotal?.sessions ?? 0 }

    private var todayTotal: DayTotal? {
        days.first { calendar.isDate($0.day, inSameDayAs: Date()) }
    }

    /// Consecutive days with a completed session, ending today. A run
    /// that ended yesterday still counts: today isn't over yet.
    var streak: Int {
        let recorded = days.map { calendar.startOfDay(for: $0.day) }
        guard !recorded.isEmpty else { return 0 }
        let today = calendar.startOfDay(for: Date())
        var cursor = today
        if !recorded.contains(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  recorded.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var run = 0
        while recorded.contains(cursor) {
            run += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return run
    }

    /// The one line the Focus pane shows, nil when there is nothing
    /// worth saying. Never zeros.
    var summary: String? {
        var segments: [String] = []
        if todaySessions > 0 {
            segments.append("\(todayMinutes) min today")
            segments.append(todaySessions == 1 ? "1 session" : "\(todaySessions) sessions")
        }
        let run = streak
        if run >= 2 {
            segments.append("\(run) day streak")
        }
        guard !segments.isEmpty else { return nil }
        return segments.joined(separator: " · ")
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(days) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
