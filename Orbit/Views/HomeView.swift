import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Environment(\.orbitWidth) private var orbitWidth
    @Query private var habits: [Habit]
    @Query private var logs: [HabitLog]
    @Query private var ideas: [Idea]
    @Query private var tasks: [OrbitTask]

    let name: String
    let navigate: (OrbitSection) -> Void

    /// Today's check-ins per habit, computed once per render. Both the counter
    /// and the habit rows below read this instead of each re-filtering the whole
    /// log table, which was O(habits × logs) every time the view rebuilt.
    private var todayPerHabit: [UUID: Int] {
        let today = OrbitDate.key()
        var counts: [UUID: Int] = [:]
        for log in logs where log.dateKey == today {
            if let id = log.habit?.id { counts[id, default: 0] += 1 }
        }
        return counts
    }

    private var todayCount: Int {
        let counts = todayPerHabit
        return habits.count { counts[$0.id, default: 0] >= $0.targetPerDay }
    }

    private var openTasks: Int { tasks.count { !$0.done } }

    private var featuredHabit: Habit? { habits.first }

    private var currentStreak: Int {
        guard let habit = featuredHabit else { return 0 }
        let habitLogs = logs.filter { $0.habit?.id == habit.id }
        let counts = HabitProgress.counts(habitLogs)
        var streak = 0
        while counts[OrbitDate.key(OrbitDate.date(daysFromToday: -streak)), default: 0] >= habit.targetPerDay { streak += 1 }
        return streak
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(OrbitDate.greeting(name: name))
                        .font(.system(size: 27, weight: .semibold))
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.system(size: 14))
                        .foregroundStyle(OrbitTheme.ink2(scheme))
                }

                HStack(spacing: 16) {
                    StatCard(icon: "flame", label: "Current streak", value: "\(currentStreak) \(currentStreak == 1 ? "day" : "days")", note: featuredHabit?.name ?? "Start a habit") { navigate(.habits) }
                    StatCard(icon: "calendar.badge.checkmark", label: "Today", value: "\(todayCount)/\(habits.count)", note: "habits completed") { navigate(.habits) }
                    StatCard(icon: "lightbulb", label: "Ideas", value: "\(ideas.count)", note: "captured locally") { navigate(.ideas) }
                    StatCard(icon: "checklist", label: "Tasks", value: "\(openTasks)", note: "open right now") { navigate(.tasks) }
                }

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Activity").font(.system(size: 15, weight: .semibold))
                        Text("\(logs.count + ideas.count + tasks.count) actions in the last 12 months")
                            .font(.system(size: 12.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                    }
                    HeatmapView(
                        completionCounts: HabitProgress.counts(logs),
                        targetPerDay: max(habits.reduce(0) { $0 + $1.targetPerDay }, 1),
                        accent: OrbitTheme.accent,
                        weeks: 52
                    )
                }
                .padding(22)
                .orbitCard()

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Today's habits").font(.system(size: 15, weight: .semibold))
                                Text("\(todayCount) of \(habits.count) complete").font(.system(size: 12)).foregroundStyle(OrbitTheme.ink2(scheme))
                            }
                            Spacer()
                            Button("View graphs") { navigate(.habits) }.buttonStyle(.orbitRow).foregroundStyle(OrbitTheme.accent)
                        }
                        let counts = todayPerHabit
                        ForEach(habits.prefix(4)) { habit in
                            let count = counts[habit.id, default: 0]
                            HStack(spacing: 12) {
                                Image(systemName: habit.icon).foregroundStyle(OrbitTheme.habitColor(habit.color))
                                    .frame(width: 34, height: 34)
                                    .background(OrbitTheme.habitColor(habit.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                                Text(habit.name).font(.system(size: 13.5, weight: .medium))
                                Spacer()
                                Text("\(count)/\(habit.targetPerDay)")
                                    .font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                                    .foregroundStyle(OrbitTheme.ink2(scheme))
                                Image(systemName: count >= habit.targetPerDay ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22)).foregroundStyle(OrbitTheme.habitColor(habit.color))
                            }
                            .padding(12)
                            .background(OrbitTheme.sunken(scheme).opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity)
                    .orbitCard()

                }
            }
            .padding(orbitWidth.pagePadding)
            .frame(maxWidth: 1220, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(OrbitTheme.canvas(scheme))
    }
}

private struct StatCard: View {
    @Environment(\.colorScheme) private var scheme
    let icon: String
    let label: String
    let value: String
    let note: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Label(label, systemImage: icon).font(.system(size: 12.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                Text(value).font(.system(size: 23, weight: .semibold)).foregroundStyle(OrbitTheme.ink(scheme))
                Text(note).font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink3(scheme))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.orbitRow)
        .orbitCard()
    }
}
