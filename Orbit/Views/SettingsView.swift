import SwiftData
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case profile = "Profile"
    case appearance = "Appearance"
    case data = "Data"
    case about = "About"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .profile: "person.crop.circle"; case .appearance: "paintpalette"; case .data: "internaldrive"; case .about: "info.circle" }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query private var habits: [Habit]
    @Query private var logs: [HabitLog]
    @Query private var ideas: [Idea]
    @Query private var ideaLinks: [IdeaLink]
    @Query private var tasks: [OrbitTask]
    @Query private var steps: [OrbitTaskStep]
    @Query private var stepLinks: [StepLink]
    @Query private var boardStrokes: [BoardStroke]
    @Query private var boardNotes: [BoardNote]
    @Query private var contacts: [Contact]
    @Query private var interactions: [Interaction]
    @Query private var settings: [AppSetting]

    @AppStorage("orbit:theme") private var themePreference = "system"
    @AppStorage("orbit:accent") private var accentHex = "#8B5CF6"
    @AppStorage("orbit:settings-section") private var selection: SettingsSection = .profile
    @State private var nameDraft = ""
    @State private var customAccent = OrbitTheme.accent
    @State private var showingWipeConfirmation = false
    @State private var exportMessage: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings").font(.system(size: 22, weight: .semibold)).padding(.horizontal, 18).padding(.bottom, 14)
                ForEach(SettingsSection.allCases) { section in
                    Button { selection = section } label: {
                        Label(section.rawValue, systemImage: section.symbol).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).frame(height: 38)
                            .background(selection == section ? OrbitTheme.accentSoft(scheme) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .foregroundStyle(selection == section ? OrbitTheme.accent : OrbitTheme.ink2(scheme))
                    }.buttonStyle(.plain)
                }
                Spacer()
            }.padding(.vertical, 28).padding(.horizontal, 12).frame(width: 220).background(OrbitTheme.sunken(scheme).opacity(0.36))
            Divider().overlay(OrbitTheme.line(scheme))
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(selection.rawValue).font(.system(size: 27, weight: .semibold))
                    sectionContent
                }.padding(36).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
        .background(OrbitTheme.canvas(scheme))
        .onAppear { nameDraft = setting("name") ?? ""; customAccent = Color(hex: accentHex) }
        .confirmationDialog("Erase all Orbit data?", isPresented: $showingWipeConfirmation, titleVisibility: .visible) {
            Button("Erase everything", role: .destructive) { wipeAllData() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Habits, ideas, tasks, people, and their history will be removed. Profile and appearance settings are preserved.") }
    }

    @ViewBuilder private var sectionContent: some View {
        switch selection {
        case .profile: profileSection
        case .appearance: appearanceSection
        case .data: dataSection
        case .about: aboutSection
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your name appears in the daily greeting. Orbit has no account or online identity.")
                .font(.system(size: 13)).foregroundStyle(OrbitTheme.ink2(scheme))
            VStack(alignment: .leading, spacing: 8) {
                Text("DISPLAY NAME").font(.system(size: 9.5, weight: .semibold)).tracking(0.9).foregroundStyle(OrbitTheme.ink3(scheme))
                HStack {
                    TextField("Name", text: $nameDraft).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                    Button("Save") { saveSetting("name", value: nameDraft) }.buttonStyle(.borderedProminent).tint(OrbitTheme.accent)
                }
            }.padding(20).orbitCard()
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Theme").font(.system(size: 15, weight: .semibold))
                HStack(spacing: 12) {
                    themeButton("light", "sun.max", "Light")
                    themeButton("dark", "moon", "Dark")
                    themeButton("system", "circle.lefthalf.filled", "System")
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Accent").font(.system(size: 15, weight: .semibold))
                HStack(spacing: 12) {
                    ForEach(["#3D6DF2", "#6366F1", "#8B5CF6", "#10B981", "#0EA5A8", "#F59E0B", "#F43F5E", "#52525B"], id: \.self) { hex in
                        Button { setAccent(hex) } label: {
                            Circle().fill(Color(hex: hex)).frame(width: 26, height: 26)
                                .overlay { Circle().stroke(OrbitTheme.ink(scheme), lineWidth: accentHex.uppercased() == hex ? 2 : 0).padding(-3) }
                        }.buttonStyle(.plain).help(hex)
                    }
                    ColorPicker("Custom", selection: $customAccent, supportsOpacity: false)
                        .onChange(of: customAccent) { if let hex = customAccent.orbitHex() { setAccent(hex) } }
                }
            }
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                countTile("Habits", habits.count); countTile("Check-ins", logs.count); countTile("Ideas", ideas.count); countTile("Tasks", tasks.count); countTile("People", contacts.count); countTile("Interactions", interactions.count)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Export").font(.system(size: 15, weight: .semibold))
                Text("Create a complete JSON snapshot that can be inspected without Orbit.").font(.system(size: 12.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                Button { exportData() } label: { Label("Export JSON", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                if let exportMessage { Text(exportMessage).font(.system(size: 11.5)).foregroundStyle(exportMessage.hasPrefix("Could") ? OrbitTheme.rose : OrbitTheme.emerald) }
            }.padding(20).orbitCard()
            VStack(alignment: .leading, spacing: 10) {
                Text("Erase all data").font(.system(size: 15, weight: .semibold))
                Text("Remove all personal content while keeping your name and appearance settings.").font(.system(size: 12.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                Button("Erase all data", role: .destructive) { showingWipeConfirmation = true }.buttonStyle(.bordered)
            }.padding(20).orbitCard()
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "circle.hexagongrid.fill").font(.system(size: 30)).foregroundStyle(OrbitTheme.accent)
                VStack(alignment: .leading, spacing: 3) { Text("Orbit 1.0.0").font(.system(size: 17, weight: .semibold)); Text("LOCAL-FIRST · KEYBOARD-FIRST · YOURS").font(.system(size: 9.5, weight: .semibold)).tracking(0.8).foregroundStyle(OrbitTheme.ink3(scheme)) }
            }
            Text("All data is stored locally in Orbit's SwiftData container. The app performs no telemetry and requires no account.")
                .font(.system(size: 13)).foregroundStyle(OrbitTheme.ink2(scheme)).frame(maxWidth: 560, alignment: .leading)
            Text("Roadmap: richer markdown, native follow-up reminders, and the Pixel companion.").font(.system(size: 12.5)).foregroundStyle(OrbitTheme.ink3(scheme))
        }.padding(22).orbitCard()
    }

    private func themeButton(_ value: String, _ symbol: String, _ label: String) -> some View {
        Button { themePreference = value; saveSetting("theme", value: value) } label: {
            VStack(spacing: 9) { Image(systemName: symbol).font(.system(size: 18)); Text(label).font(.system(size: 11.5, weight: .medium)) }
                .frame(width: 112, height: 78).background(themePreference == value ? OrbitTheme.accentSoft(scheme) : OrbitTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 11))
                .overlay { RoundedRectangle(cornerRadius: 11).stroke(themePreference == value ? OrbitTheme.accent : OrbitTheme.line(scheme)) }
        }.buttonStyle(.plain)
    }
    private func countTile(_ label: String, _ value: Int) -> some View { VStack(alignment: .leading, spacing: 6) { Text("\(value)").font(.system(size: 20, weight: .semibold)).monospacedDigit(); Text(label).font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink2(scheme)) }.padding(16).frame(maxWidth: .infinity, alignment: .leading).orbitCard() }
    private func setting(_ key: String) -> String? { settings.first(where: { $0.key == key })?.value }
    private func saveSetting(_ key: String, value: String) { if let existing = settings.first(where: { $0.key == key }) { existing.value = value } else { modelContext.insert(AppSetting(key: key, value: value)) }; try? modelContext.save() }
    private func setAccent(_ hex: String) { accentHex = hex; saveSetting("accent", value: hex) }
    private func exportData() { do { try ExportService.export(habits: habits, habitLogs: logs, ideas: ideas, ideaLinks: ideaLinks, tasks: tasks, taskSteps: steps, stepLinks: stepLinks, boardStrokes: boardStrokes, boardNotes: boardNotes, contacts: contacts, interactions: interactions, settings: settings); exportMessage = "Export finished." } catch { exportMessage = "Could not export: \(error.localizedDescription)" } }
    private func wipeAllData() {
        logs.forEach(modelContext.delete); habits.forEach(modelContext.delete); ideaLinks.forEach(modelContext.delete); ideas.forEach(modelContext.delete); stepLinks.forEach(modelContext.delete); boardStrokes.forEach(modelContext.delete); boardNotes.forEach(modelContext.delete); steps.forEach(modelContext.delete); tasks.forEach(modelContext.delete); interactions.forEach(modelContext.delete); contacts.forEach(modelContext.delete); try? modelContext.save()
        UserDefaults.standard.set(true, forKey: "orbit:tasks-seeded"); UserDefaults.standard.set(true, forKey: "orbit:people-seeded")
    }
}
