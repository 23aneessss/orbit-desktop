import SwiftData
import SwiftUI

@main
struct OrbitApp: App {
    private let container: ModelContainer = {
        let schema = Schema([
            Habit.self,
            HabitLog.self,
            Idea.self,
            IdeaLink.self,
            IdeaFolder.self,
            OrbitTask.self,
            OrbitTaskStep.self,
            StepLink.self,
            BoardStroke.self,
            BoardNote.self,
            Contact.self,
            Interaction.self,
            AppSetting.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create Orbit's local data store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .frame(minWidth: 1040, minHeight: 680)
        }
        .modelContainer(container)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Open Command Palette") {
                    NotificationCenter.default.post(name: .openCommandPalette, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let openCommandPalette = Notification.Name("orbit.open-command-palette")
}
