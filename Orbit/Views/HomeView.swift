import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query private var habits: [Habit]
    @Query private var logs: [HabitLog]
    @Query private var ideas: [Idea]
    @Query private var contacts: [Contact]
    @Query private var interactions: [Interaction]

    let name: String
    let navigate: (OrbitSection) -> Void

    private var todayCount: Int {
        let today = OrbitDate.key()
        return Set(logs.filter { $0.dateKey == today }.compactMap { $0.habit?.id }).count
    }

    private var dueContacts: [Contact] {
        contacts.filter { $0.nextFollowUpKey.map { $0 <= OrbitDate.key() } ?? false }
            .sorted { ($0.nextFollowUpKey ?? "") < ($1.nextFollowUpKey ?? "") }
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
                    StatCard(icon: "flame", label: "Current streak", value: "1 days", note: "Deep work") { navigate(.habits) }
                    StatCard(icon: "calendar.badge.checkmark", label: "Today", value: "\(todayCount)/\(habits.count)", note: "habits completed") { navigate(.habits) }
                    StatCard(icon: "lightbulb", label: "Ideas", value: "\(ideas.count)", note: "captured locally") { navigate(.ideas) }
                    StatCard(icon: "person.2", label: "People", value: "\(contacts.count)", note: "\(dueContacts.count) follow-ups due") { navigate(.people) }
                }

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Activity").font(.system(size: 15, weight: .semibold))
                        Text("\(logs.count + ideas.count + interactions.count) actions in the last 12 months")
                            .font(.system(size: 12.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                    }
                    HeatmapView(dateKeys: Set(logs.map(\.dateKey)), accent: OrbitTheme.accent, weeks: 52)
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
                            Button("View graphs") { navigate(.habits) }.buttonStyle(.plain).foregroundStyle(OrbitTheme.accent)
                        }
                        ForEach(habits.prefix(4)) { habit in
                            HStack(spacing: 12) {
                                Image(systemName: habit.icon).foregroundStyle(OrbitTheme.habitColor(habit.color))
                                    .frame(width: 34, height: 34)
                                    .background(OrbitTheme.habitColor(habit.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                                Text(habit.name).font(.system(size: 13.5, weight: .medium))
                                Spacer()
                                Image(systemName: logs.contains(where: { $0.habit?.id == habit.id && $0.dateKey == OrbitDate.key() }) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22)).foregroundStyle(OrbitTheme.habitColor(habit.color))
                            }
                            .padding(12)
                            .background(OrbitTheme.sunken(scheme).opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity)
                    .orbitCard()

                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack { Text("Follow-ups").font(.system(size: 15, weight: .semibold)); Spacer(); Button("View all") { navigate(.people) }.buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(OrbitTheme.accent) }
                            if dueContacts.isEmpty {
                                Text("Nothing due. Your relationship queue is clear.").font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                            } else {
                                ForEach(dueContacts.prefix(4)) { contact in
                                    HStack(spacing: 9) {
                                        PersonAvatar(name: contact.name, size: 30)
                                        VStack(alignment: .leading, spacing: 3) { Text(contact.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1); FollowUpBadge(dateKey: contact.nextFollowUpKey) }
                                        Spacer()
                                        Button { contact.nextFollowUpKey = nil; try? modelContext.save() } label: { Image(systemName: "checkmark.circle") }.buttonStyle(.plain).foregroundStyle(OrbitTheme.ink3(scheme)).help("Mark follow-up done")
                                    }
                                }
                            }
                        }.padding(18).orbitCard()

                        VStack(alignment: .leading, spacing: 14) {
                            Text("Recent ideas").font(.system(size: 15, weight: .semibold))
                            ForEach(ideas.prefix(3)) { idea in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(idea.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                    Text(idea.content).font(.system(size: 11)).foregroundStyle(OrbitTheme.ink2(scheme)).lineLimit(2)
                                }
                            }
                        }.padding(18).orbitCard()
                    }
                    .frame(width: 310, alignment: .leading)
                }
            }
            .padding(32)
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
        .buttonStyle(.plain)
        .orbitCard()
    }
}
