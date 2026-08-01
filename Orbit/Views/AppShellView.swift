import SwiftData
import SwiftUI

enum OrbitSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case habits = "Habits"
    case ideas = "Ideas"
    case canvas = "Canvas"
    case tasks = "Tasks"
    case settings = "Settings"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house"
        case .habits: "flame"
        case .ideas: "lightbulb"
        case .canvas: "point.3.connected.trianglepath.dotted"
        case .tasks: "checklist"
        case .settings: "gearshape"
        }
    }
}

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query private var habits: [Habit]
    @Query private var logs: [HabitLog]
    @Query private var settings: [AppSetting]

    @AppStorage("orbit:sidebar-collapsed") private var sidebarCollapsed = false
    @AppStorage("orbit:workspace") private var workspaceID = ""
    @AppStorage("orbit:theme") private var themePreference = "system"
    @AppStorage("orbit:accent") private var accentHex = "#8B5CF6"
    @State private var selection: OrbitSection = .home
    @State private var commandPalettePresented = false
    @State private var requestedIdeaID: UUID?
    @State private var overlaySidebar = false

    private var displayName: String {
        settings.first(where: { $0.key == "name" })?.value ?? ""
    }

    /// One pass over the logs instead of re-scanning the whole table per habit.
    /// The old shape was O(habits × logs) on *every* render, which is what made
    /// clicking around the app feel laggy once a year of check-ins had built up.
    private var completedToday: Int {
        let today = OrbitDate.key()
        var perHabit: [UUID: Int] = [:]
        for log in logs where log.dateKey == today {
            if let id = log.habit?.id { perHabit[id, default: 0] += 1 }
        }
        return habits.count { perHabit[$0.id, default: 0] >= $0.targetPerDay }
    }

    /// How the menu presents itself at the current window width.
    private enum SidebarMode { case expanded, rail, hidden }

    private func sidebarMode(for widthClass: OrbitWidthClass) -> SidebarMode {
        switch widthClass {
        case .compact: .hidden          // becomes a drawer over the content
        case .medium: .rail             // icons only, no room for labels
        case .regular: sidebarCollapsed ? .rail : .expanded
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let widthClass = OrbitWidthClass(proxy.size.width)
            let mode = sidebarMode(for: widthClass)

            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    if mode != .hidden {
                        sidebar(mode)
                            .frame(width: mode == .expanded ? 256 : 72)
                        Divider().overlay(OrbitTheme.line(scheme))
                    }

                    VStack(spacing: 0) {
                        topbar(widthClass, mode: mode)
                        Divider().overlay(OrbitTheme.line(scheme))
                        content
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                // Below the compact threshold the menu would eat most of the
                // window, so it slides over the content instead of displacing it.
                if mode == .hidden, overlaySidebar {
                    Color.black.opacity(0.32)
                        .ignoresSafeArea()
                        .onTapGesture { setOverlay(false) }
                        .accessibilityLabel("Close menu")

                    sidebar(.expanded)
                        .frame(width: 244)
                        .background(OrbitTheme.canvas(scheme))
                        .overlay(alignment: .trailing) { Divider().overlay(OrbitTheme.line(scheme)) }
                        .shadow(color: .black.opacity(0.3), radius: 18, x: 5)
                        .transition(.move(edge: .leading))
                }
            }
            .environment(\.orbitWidth, widthClass)
            .onChange(of: mode) { _, updated in
                if updated != .hidden { overlaySidebar = false }
            }
        }
        .background(OrbitTheme.canvas(scheme))
        .foregroundStyle(OrbitTheme.ink(scheme))
        .preferredColorScheme(preferredColorScheme)
        .animation(.easeOut(duration: 0.22), value: sidebarCollapsed)
        .task {
            SeedService.seedIfNeeded(context: modelContext)
            // Creates "ETIC" on first run and adopts every pre-workspace idea.
            if let home = WorkspaceService.bootstrap(context: modelContext), workspaceID.isEmpty {
                workspaceID = home.id.uuidString
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCommandPalette)) { _ in
            commandPalettePresented = true
        }
        .sheet(isPresented: $commandPalettePresented) {
            CommandPaletteView(selection: $selection, isPresented: $commandPalettePresented, requestedIdeaID: $requestedIdeaID)
        }
    }

    private func setOverlay(_ shown: Bool) {
        withAnimation(.easeOut(duration: 0.18)) { overlaySidebar = shown }
    }

    private func sidebar(_ mode: SidebarMode) -> some View {
        let rail = mode == .rail

        return VStack(spacing: 0) {
            if rail {
                VStack(spacing: 10) {
                    OrbitLogo()
                    sidebarToggle
                }
                .padding(.top, 14)
                .frame(height: 92, alignment: .top)
                .transition(.opacity)
            } else {
                HStack(spacing: 12) {
                    OrbitLogo()
                    Text("Orbit").font(.system(size: 18, weight: .semibold))
                    Spacer()
                    sidebarToggle
                }
                .padding(.horizontal, 16)
                .frame(height: 64)
                .transition(.opacity)
            }

            Button { commandPalettePresented = true; setOverlay(false) } label: {
                HStack(spacing: 11) {
                    Image(systemName: "magnifyingglass")
                    if !rail {
                        Text("Search")
                        Spacer()
                        Text("⌘K").font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(OrbitTheme.sunken(scheme), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                .foregroundStyle(OrbitTheme.ink3(scheme))
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .background(OrbitTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(OrbitTheme.line(scheme)) }
            }
            .buttonStyle(.orbitRow)
            .padding(.horizontal, rail ? 10 : 16)

            if !rail {
                Text("MENU")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(OrbitTheme.ink3(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 8)
            } else {
                Spacer().frame(height: 18)
            }

            ForEach(OrbitSection.allCases.filter { $0 != .settings }) { section in
                sidebarItem(section, rail: rail)
            }

            WorkspaceSidebar(rail: rail) {
                selection = .ideas
                setOverlay(false)
            }

            Spacer(minLength: 8)
            sidebarItem(.settings, rail: rail)

            if !rail {
                HStack(spacing: 12) {
                    ProgressRing(progress: habits.isEmpty ? 0 : Double(completedToday) / Double(habits.count))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Today").font(.system(size: 13, weight: .semibold))
                        Text("\(completedToday) of \(habits.count) habits")
                            .font(.system(size: 11.5))
                            .foregroundStyle(OrbitTheme.ink2(scheme))
                    }
                    Spacer()
                }
                .padding(12)
                .orbitCard()
                .padding(16)
            } else {
                ProgressRing(progress: habits.isEmpty ? 0 : Double(completedToday) / Double(habits.count))
                    .padding(.vertical, 18)
            }
        }
        .background(OrbitTheme.canvas(scheme))
        .clipped()
    }

    private var sidebarToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.22)) { sidebarCollapsed.toggle() }
        } label: {
            Image(systemName: sidebarCollapsed ? "sidebar.right" : "sidebar.leading")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.orbitRow)
        .foregroundStyle(OrbitTheme.ink3(scheme))
        .help(sidebarCollapsed ? "Expand sidebar" : "Collapse sidebar")
        .accessibilityLabel(sidebarCollapsed ? "Expand sidebar" : "Collapse sidebar")
    }

    private func sidebarItem(_ section: OrbitSection, rail: Bool) -> some View {
        Button {
            selection = section
            setOverlay(false)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: section.symbol)
                    .font(.system(size: 15, weight: selection == section ? .semibold : .regular))
                    .frame(width: 20)
                if !rail {
                    Text(section.rawValue).font(.system(size: 14, weight: .medium))
                    Spacer()
                }
            }
            .foregroundStyle(selection == section ? OrbitTheme.accent : OrbitTheme.ink2(scheme))
            .padding(.horizontal, rail ? 18 : 16)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(selection == section ? OrbitTheme.accentSoft(scheme) : .clear,
                        in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.orbitRow)
        .padding(.horizontal, rail ? 9 : 16)
        .help(section.rawValue)
    }

    private func topbar(_ widthClass: OrbitWidthClass, mode: SidebarMode) -> some View {
        HStack(spacing: 9) {
            if mode == .hidden {
                Button { setOverlay(!overlaySidebar) } label: {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.orbitRow)
                .foregroundStyle(OrbitTheme.ink2(scheme))
                .help("Show menu")
                .accessibilityLabel("Show menu")
            }

            // The breadcrumb prefix and the date are the first things to go —
            // the section name and the profile button are what actually get used.
            if widthClass == .regular {
                Text("Orbit").foregroundStyle(OrbitTheme.ink3(scheme))
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(OrbitTheme.ink3(scheme))
            }

            Text(selection.rawValue).fontWeight(.medium).lineLimit(1)

            Spacer(minLength: 8)

            if widthClass == .regular {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .foregroundStyle(OrbitTheme.ink3(scheme)).lineLimit(1)
            } else if widthClass == .medium {
                Text(Date.now.formatted(.dateTime.month(.abbreviated).day()))
                    .foregroundStyle(OrbitTheme.ink3(scheme)).lineLimit(1)
            }

            Button { selection = .settings } label: {
                let initial = displayName.prefix(1).uppercased()
                Text(initial.isEmpty ? "A" : initial)
                    .font(.system(size: widthClass.isCompact ? 11 : 12, weight: .semibold))
                    .frame(width: widthClass.isCompact ? 28 : 34, height: widthClass.isCompact ? 28 : 34)
                    .background(Color(hex: "C7F4E9"), in: Circle())
                    .foregroundStyle(Color(hex: "166B5B"))
            }
            .buttonStyle(.orbitRow)
        }
        .font(.system(size: 13))
        .padding(.horizontal, widthClass.isCompact ? 14 : 28)
        .frame(height: 56)
        .background(OrbitTheme.canvas(scheme))
    }


    @ViewBuilder private var content: some View {
        switch selection {
        case .home: HomeView(name: displayName, navigate: { selection = $0 })
        case .habits: HabitsView()
        case .canvas: IdeaCanvasView()
        case .ideas: IdeasView(requestedIdeaID: $requestedIdeaID)
        case .tasks: TasksView()
        case .settings: SettingsView()
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch themePreference {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

private struct OrbitLogo: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "A873FF"), OrbitTheme.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
            Ellipse().stroke(.white.opacity(0.92), lineWidth: 1.8)
                .frame(width: 22, height: 13).rotationEffect(.degrees(-35))
            Circle().fill(.white).frame(width: 7, height: 7)
            Circle().fill(.white).frame(width: 4.5, height: 4.5).offset(x: 8, y: -8)
        }
        .frame(width: 32, height: 32)
        .accessibilityLabel("Orbit")
    }
}

private struct ProgressRing: View {
    let progress: Double
    var body: some View {
        ZStack {
            Circle().stroke(OrbitTheme.accent.opacity(0.15), lineWidth: 4)
            Circle().trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(OrbitTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 34, height: 34)
        .accessibilityLabel("Today's habit progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

private struct CommandPaletteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query(sort: \Idea.updatedAt, order: .reverse) private var ideas: [Idea]
    @Query private var logs: [HabitLog]
    @Binding var selection: OrbitSection
    @Binding var isPresented: Bool
    @Binding var requestedIdeaID: UUID?
    @State private var query = ""

    private var results: [OrbitSection] {
        query.isEmpty ? OrbitSection.allCases : OrbitSection.allCases.filter { $0.rawValue.localizedStandardContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Search Orbit", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
            }
            .padding(18)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    paletteHeader("GO TO")
                    ForEach(results) { section in paletteButton(section.rawValue, symbol: section.symbol) { selection = section; isPresented = false } }

                    if query.isEmpty || "new idea new task new person".localizedStandardContains(query) {
                        paletteHeader("ACTIONS")
                        paletteButton("New idea", symbol: "lightbulb") { modelContext.insert(Idea(title: "", content: "")); try? modelContext.save(); selection = .ideas; isPresented = false }
                        paletteButton("New task", symbol: "checklist") { modelContext.insert(OrbitTask(title: "Untitled task")); try? modelContext.save(); selection = .tasks; isPresented = false }
                    }

                    if query.isEmpty || habits.contains(where: { $0.name.localizedStandardContains(query) }) {
                        paletteHeader("LOG TODAY")
                        ForEach(habits.filter { query.isEmpty || $0.name.localizedStandardContains(query) }) { habit in
                            let count = HabitProgress.count(in: logs.filter { $0.habit?.id == habit.id })
                            let done = count >= habit.targetPerDay
                            paletteButton("\(habit.name)  \(count)/\(habit.targetPerDay)", symbol: done ? "checkmark.circle.fill" : "circle") { toggleHabit(habit) }
                        }
                    }

                    let matchingIdeas = ideas.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
                    if !matchingIdeas.isEmpty {
                        paletteHeader("IDEAS")
                        ForEach(matchingIdeas.prefix(8)) { idea in paletteButton(idea.title.isEmpty ? "Untitled" : idea.title, symbol: "lightbulb") { requestedIdeaID = idea.id; selection = .ideas; isPresented = false } }
                    }

                }.padding(10)
            }
        }
        .frame(minWidth: 300, idealWidth: 540, minHeight: 260, idealHeight: 420)
    }

    private func paletteHeader(_ title: String) -> some View {
        Text(title).font(.system(size: 9.5, weight: .semibold)).tracking(0.9).foregroundStyle(OrbitTheme.ink3(scheme)).padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 3)
    }

    private func paletteButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.system(size: 12.5)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 34).contentShape(Rectangle()) }
            .buttonStyle(.orbitRow)
    }

    private func toggleHabit(_ habit: Habit) {
        let today = OrbitDate.key()
        let existing = logs.filter { $0.habit?.id == habit.id && $0.dateKey == today }
        if existing.count >= habit.targetPerDay { existing.forEach(modelContext.delete) }
        else { modelContext.insert(HabitLog(dateKey: today, habit: habit)) }
        try? modelContext.save()
    }
}









