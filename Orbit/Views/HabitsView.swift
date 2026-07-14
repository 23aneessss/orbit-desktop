import SwiftData
import SwiftUI

struct HabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var logs: [HabitLog]

    @State private var editorRequest: HabitEditorRequest?
    @State private var habitToDelete: Habit?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Habits").font(.system(size: 27, weight: .semibold))
                        Text("\(habits.count) active · \(logs.count) check-ins. Click a square to advance that day's count.")
                            .font(.system(size: 13.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                    }
                    Spacer()
                    Button { editorRequest = HabitEditorRequest(habit: nil) } label: {
                        Label("New habit", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OrbitTheme.accent)
                }

                if habits.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "flame").font(.system(size: 22)).foregroundStyle(OrbitTheme.accent)
                            .frame(width: 50, height: 50)
                            .background(OrbitTheme.accentSoft(scheme), in: RoundedRectangle(cornerRadius: 14))
                        Text("Build your first streak").font(.system(size: 17, weight: .semibold))
                        Text("Choose what to track, how often it happens each day, and your weekly rhythm.")
                            .font(.system(size: 12.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                        Button("Create a habit") { editorRequest = HabitEditorRequest(habit: nil) }
                            .buttonStyle(.borderedProminent).tint(OrbitTheme.accent)
                    }
                    .padding(48).frame(maxWidth: .infinity).orbitCard()
                } else {
                    ForEach(habits) { habit in
                        let habitLogs = logs.filter { $0.habit?.id == habit.id }
                        HabitCard(
                            habit: habit,
                            logs: habitLogs,
                            incrementToday: { increment(habit, on: OrbitDate.key()) },
                            decrementToday: { decrement(habit, on: OrbitDate.key()) },
                            advanceDate: { advance(habit, on: $0) },
                            edit: { editorRequest = HabitEditorRequest(habit: habit) },
                            delete: { habitToDelete = habit }
                        )
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 1220, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(OrbitTheme.canvas(scheme))
        .sheet(item: $editorRequest) { request in
            HabitEditorSheet(
                habit: request.habit,
                onSave: { name, icon, color, targetPerDay, targetPerWeek in
                    saveHabit(request.habit, name: name, icon: icon, color: color, targetPerDay: targetPerDay, targetPerWeek: targetPerWeek)
                },
                onDelete: request.habit.map { habit in { deleteHabit(habit) } }
            )
        }
        .alert("Delete habit?", isPresented: deleteAlertPresented) {
            Button("Cancel", role: .cancel) { habitToDelete = nil }
            Button("Delete", role: .destructive) {
                if let habitToDelete { deleteHabit(habitToDelete) }
            }
        } message: {
            Text("This removes the habit and all of its check-in history. This cannot be undone.")
        }
    }

    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: { habitToDelete != nil },
            set: { if !$0 { habitToDelete = nil } }
        )
    }

    private func logs(for habit: Habit, on dateKey: String) -> [HabitLog] {
        logs.filter { $0.habit?.id == habit.id && $0.dateKey == dateKey }
    }

    private func increment(_ habit: Habit, on dateKey: String) {
        guard logs(for: habit, on: dateKey).count < habit.targetPerDay else { return }
        modelContext.insert(HabitLog(dateKey: dateKey, habit: habit))
        try? modelContext.save()
    }

    private func decrement(_ habit: Habit, on dateKey: String) {
        guard let existing = logs(for: habit, on: dateKey).max(by: { $0.createdAt < $1.createdAt }) else { return }
        modelContext.delete(existing)
        try? modelContext.save()
    }

    private func advance(_ habit: Habit, on dateKey: String) {
        let existing = logs(for: habit, on: dateKey)
        if existing.count >= habit.targetPerDay {
            existing.forEach(modelContext.delete)
            try? modelContext.save()
        } else {
            increment(habit, on: dateKey)
        }
    }

    private func saveHabit(_ habit: Habit?, name: String, icon: String, color: String, targetPerDay: Int, targetPerWeek: Int) {
        if let habit {
            habit.name = name
            habit.icon = icon
            habit.color = color
            habit.targetPerDay = targetPerDay
            habit.targetPerWeek = targetPerWeek
        } else {
            modelContext.insert(Habit(name: name, icon: icon, color: color, targetPerDay: targetPerDay, targetPerWeek: targetPerWeek))
        }
        try? modelContext.save()
    }

    private func deleteHabit(_ habit: Habit) {
        logs.filter { $0.habit?.id == habit.id }.forEach(modelContext.delete)
        modelContext.delete(habit)
        try? modelContext.save()
        habitToDelete = nil
    }
}

private struct HabitEditorRequest: Identifiable {
    let id = UUID()
    let habit: Habit?
}

private struct HabitCard: View {
    @Environment(\.colorScheme) private var scheme
    let habit: Habit
    let logs: [HabitLog]
    let incrementToday: () -> Void
    let decrementToday: () -> Void
    let advanceDate: (String) -> Void
    let edit: () -> Void
    let delete: () -> Void

    private var todayCount: Int { HabitProgress.count(in: logs) }
    private var completedDaysThisWeek: Int { HabitProgress.completedDaysThisWeek(for: habit, logs: logs) }

    var body: some View {
        let accent = OrbitTheme.habitColor(habit.color)
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: habit.icon).font(.system(size: 17)).foregroundStyle(accent)
                    .frame(width: 42, height: 42).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 4) {
                    Text(habit.name).font(.system(size: 16, weight: .semibold))
                    Text("\(logs.count) check-ins · \(habit.targetPerDay)× daily · \(habit.targetPerWeek)-day weekly goal")
                        .font(.system(size: 12.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                }
                Spacer()

                HStack(spacing: 0) {
                    Button(action: decrementToday) {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 36, height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(todayCount == 0)
                    .opacity(todayCount == 0 ? 0.28 : 1)
                    .help("Remove one check-in for today")

                    Divider().frame(height: 20)

                    VStack(spacing: 1) {
                        Text("TODAY")
                            .font(.system(size: 8.5, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(OrbitTheme.ink3(scheme))
                        Text("\(todayCount) of \(habit.targetPerDay)")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(todayCount >= habit.targetPerDay ? accent : OrbitTheme.ink(scheme))
                    }
                    .frame(width: 64, height: 38)

                    Divider().frame(height: 20)

                    Button(action: incrementToday) {
                        Image(systemName: todayCount >= habit.targetPerDay ? "checkmark" : "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 36, height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)
                    .disabled(todayCount >= habit.targetPerDay)
                    .opacity(todayCount >= habit.targetPerDay ? 0.55 : 1)
                    .help(todayCount >= habit.targetPerDay ? "Daily goal complete" : "Add one check-in for today")
                }
                .background(
                    todayCount >= habit.targetPerDay ? accent.opacity(0.12) : OrbitTheme.sunken(scheme),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(todayCount >= habit.targetPerDay ? accent.opacity(0.45) : OrbitTheme.line(scheme))
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Today's progress, \(todayCount) of \(habit.targetPerDay)")

                Menu {
                    Button("Edit habit", systemImage: "pencil", action: edit)
                    Divider()
                    Button("Delete habit", systemImage: "trash", role: .destructive, action: delete)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Habit options")
            }

            HeatmapView(
                completionCounts: HabitProgress.counts(logs),
                targetPerDay: habit.targetPerDay,
                accent: accent,
                weeks: 52,
                advanceDate: advanceDate
            )

            HStack(spacing: 10) {
                Text("This week").font(.system(size: 12.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(OrbitTheme.sunken(scheme))
                        Capsule().fill(accent)
                            .frame(width: proxy.size.width * min(Double(completedDaysThisWeek) / Double(habit.targetPerWeek), 1))
                    }
                }
                .frame(height: 6)
                Text("\(completedDaysThisWeek)/\(habit.targetPerWeek) days")
                    .font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink3(scheme)).monospacedDigit()
            }
        }
        .padding(22)
        .orbitCard()
    }
}

struct HeatmapView: View {
    @Environment(\.colorScheme) private var scheme
    let completionCounts: [String: Int]
    let targetPerDay: Int
    let accent: Color
    let weeks: Int
    var advanceDate: ((String) -> Void)? = nil

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 5) {
                Color.clear.frame(width: 16, height: 1)
                HStack(spacing: 0) {
                    ForEach(monthLabels, id: \.self) { month in
                        Text(month)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(OrbitTheme.ink3(scheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            LazyVGrid(
                columns: [GridItem(.fixed(16), spacing: 5)] + Array(repeating: GridItem(.flexible(minimum: 5), spacing: 3), count: weeks),
                spacing: 3
            ) {
                ForEach(0..<7, id: \.self) { day in
                    Text(day == 0 ? "M" : day == 2 ? "W" : day == 4 ? "F" : "")
                        .font(.system(size: 8.5)).foregroundStyle(OrbitTheme.ink3(scheme))
                        .frame(maxWidth: .infinity)
                    ForEach(0..<weeks, id: \.self) { week in
                        let offset = -((weeks - 1 - week) * 7 + (6 - day))
                        let key = OrbitDate.key(OrbitDate.date(daysFromToday: offset))
                        heatmapCell(key: key)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var monthLabels: [String] {
        let formatter = DateFormatter()
        formatter.locale = .current
        let symbols = formatter.shortMonthSymbols ?? ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let currentMonth = OrbitDate.calendar.component(.month, from: .now) - 1
        return (1...12).map { symbols[(currentMonth + $0) % 12] }
    }

    @ViewBuilder private func heatmapCell(key: String) -> some View {
        let count = completionCounts[key, default: 0]
        let ratio = min(Double(count) / Double(max(targetPerDay, 1)), 1)
        let fill = count == 0 ? OrbitTheme.sunken(scheme) : accent.opacity(0.2 + 0.8 * ratio)
        let square = RoundedRectangle(cornerRadius: 2)
            .fill(fill)
            .aspectRatio(1, contentMode: .fit)
        if let advanceDate {
            Button { advanceDate(key) } label: { square }
                .buttonStyle(.plain)
                .help("\(key) · \(count) of \(targetPerDay). Click to advance; after the goal, click to reset.")
                .accessibilityLabel(key)
                .accessibilityValue("\(count) of \(targetPerDay) check-ins")
        } else {
            square.help("\(key) · \(count) check-ins")
        }
    }
}

private struct HabitEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let habit: Habit?
    let onSave: (String, String, String, Int, Int) -> Void
    let onDelete: (() -> Void)?

    @State private var name: String
    @State private var icon: String
    @State private var color: String
    @State private var targetPerDay: Int
    @State private var targetPerWeek: Int
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    private let icons = ["target", "flame", "figure.run", "figure.strengthtraining.traditional", "book.fill", "drop.fill", "pencil.line", "brain.head.profile", "leaf.fill", "moon.stars.fill"]
    private let colors = ["accent", "cobalt", "emerald", "teal", "amber", "rose"]

    init(habit: Habit?, onSave: @escaping (String, String, String, Int, Int) -> Void, onDelete: (() -> Void)?) {
        self.habit = habit
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: habit?.name ?? "")
        _icon = State(initialValue: habit?.icon ?? "target")
        _color = State(initialValue: habit?.color ?? "accent")
        _targetPerDay = State(initialValue: habit?.targetPerDay ?? 1)
        _targetPerWeek = State(initialValue: habit?.targetPerWeek ?? 5)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(habit == nil ? "New habit" : "Edit habit")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Define what a completed day means for this habit.")
                        .font(.system(size: 12.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                }
                Spacer()
            }
            .padding(24)

            Divider()

            Form {
                Section("Habit") {
                    TextField("Name", text: $name)
                        .focused($nameFocused)
                        .accessibilityLabel("Habit name")

                    LabeledContent("Icon") {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 5), spacing: 6) {
                            ForEach(icons, id: \.self) { symbol in
                                Button { icon = symbol } label: {
                                    Image(systemName: symbol).frame(width: 30, height: 30)
                                        .foregroundStyle(icon == symbol ? OrbitTheme.habitColor(color) : OrbitTheme.ink2(scheme))
                                        .background(icon == symbol ? OrbitTheme.habitColor(color).opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(symbol)
                                .accessibilityAddTraits(icon == symbol ? .isSelected : [])
                            }
                        }
                    }

                    LabeledContent("Color") {
                        HStack(spacing: 10) {
                            ForEach(colors, id: \.self) { value in
                                Button { color = value } label: {
                                    Circle().fill(OrbitTheme.habitColor(value)).frame(width: 20, height: 20)
                                        .overlay { Circle().stroke(OrbitTheme.ink(scheme).opacity(color == value ? 0.55 : 0), lineWidth: 2).padding(-3) }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(value.capitalized)
                                .accessibilityAddTraits(color == value ? .isSelected : [])
                            }
                        }
                    }
                }

                Section("Goal") {
                    Stepper(value: $targetPerDay, in: 1...20) {
                        LabeledContent("Times per day", value: "\(targetPerDay)")
                    }
                    Stepper(value: $targetPerWeek, in: 1...7) {
                        LabeledContent("Days per week", value: "\(targetPerWeek)")
                    }
                    Text("Each check-in darkens the day's square. The square reaches full color when the daily goal is complete.")
                        .font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if onDelete != nil {
                    Button("Delete habit", role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), icon, color, targetPerDay, targetPerWeek)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(OrbitTheme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
        }
        .frame(width: 500, height: 590)
        .onAppear { nameFocused = true }
        .alert("Delete habit?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete?()
                dismiss()
            }
        } message: {
            Text("This removes the habit and all of its check-in history. This cannot be undone.")
        }
    }
}
