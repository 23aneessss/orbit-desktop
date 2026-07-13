import SwiftData
import SwiftUI

struct HabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var logs: [HabitLog]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Habits").font(.system(size: 27, weight: .semibold))
                        Text("\(habits.count) active · \(logs.count) check-ins. Click any square to edit history.")
                            .font(.system(size: 13.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                    }
                    Spacer()
                    Button { addHabit() } label: { Label("New habit", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).tint(OrbitTheme.accent)
                }

                ForEach(habits) { habit in
                    HabitCard(habit: habit, logs: logs.filter { $0.habit?.id == habit.id }) {
                        toggleToday(habit)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 1220, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(OrbitTheme.canvas(scheme))
    }

    private func toggleToday(_ habit: Habit) {
        let today = OrbitDate.key()
        if let existing = logs.first(where: { $0.habit?.id == habit.id && $0.dateKey == today }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(HabitLog(dateKey: today, habit: habit))
        }
        try? modelContext.save()
    }

    private func addHabit() {
        modelContext.insert(Habit(name: "New habit", icon: "target", color: "accent", targetPerWeek: 5))
        try? modelContext.save()
    }
}

private struct HabitCard: View {
    @Environment(\.colorScheme) private var scheme
    let habit: Habit
    let logs: [HabitLog]
    let toggleToday: () -> Void

    private var doneToday: Bool { logs.contains { $0.dateKey == OrbitDate.key() } }
    private var thisWeek: Int {
        let interval = OrbitDate.calendar.dateInterval(of: .weekOfYear, for: .now)
        return logs.filter { log in
            guard let date = OrbitDate.keyFormatter.date(from: log.dateKey), let interval else { return false }
            return interval.contains(date)
        }.count
    }

    var body: some View {
        let accent = OrbitTheme.habitColor(habit.color)
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: habit.icon).font(.system(size: 17)).foregroundStyle(accent)
                    .frame(width: 42, height: 42).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 4) {
                    Text(habit.name).font(.system(size: 16, weight: .semibold))
                    Text("\(logs.count) check-ins · weekly goal \(habit.targetPerWeek)")
                        .font(.system(size: 12.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                }
                Spacer()
                Button(action: toggleToday) {
                    Label(doneToday ? "Done today" : "Mark today", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent).tint(doneToday ? accent : OrbitTheme.ink3(scheme))
            }

            HeatmapView(dateKeys: Set(logs.map(\.dateKey)), accent: accent, weeks: 52)

            HStack(spacing: 10) {
                Text("This week").font(.system(size: 12.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(OrbitTheme.sunken(scheme))
                        Capsule().fill(accent).frame(width: proxy.size.width * min(Double(thisWeek) / Double(habit.targetPerWeek), 1))
                    }
                }
                .frame(width: 130, height: 5)
                Text("\(thisWeek)/\(habit.targetPerWeek)").font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink3(scheme))
            }
        }
        .padding(22)
        .orbitCard()
    }
}

struct HeatmapView: View {
    @Environment(\.colorScheme) private var scheme
    let dateKeys: Set<String>
    let accent: Color
    let weeks: Int

    var body: some View {
        HStack(alignment: .top, spacing: 3) {
            VStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { day in
                    Text(day == 0 ? "M" : day == 2 ? "W" : day == 4 ? "F" : "")
                        .font(.system(size: 8.5)).foregroundStyle(OrbitTheme.ink3(scheme))
                        .frame(width: 12, height: 11)
                }
            }
            GeometryReader { proxy in
                let gap: CGFloat = 3
                let cell = max(5, min(11, (proxy.size.width - CGFloat(weeks - 1) * gap) / CGFloat(weeks)))
                HStack(spacing: gap) {
                    ForEach(0..<weeks, id: \.self) { week in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { day in
                                let offset = -((weeks - 1 - week) * 7 + (6 - day))
                                let key = OrbitDate.key(OrbitDate.date(daysFromToday: offset))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(dateKeys.contains(key) ? accent : OrbitTheme.sunken(scheme))
                                    .frame(width: cell, height: cell)
                                    .help(key)
                            }
                        }
                    }
                }
            }
            .frame(height: 95)
        }
        .frame(maxWidth: .infinity)
    }
}

