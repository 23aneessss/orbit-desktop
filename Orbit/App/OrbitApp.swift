import AppKit
import SwiftData
import SwiftUI

enum OrbitAppIcon {
    /// Swaps the running app's Dock icon and also stamps the choice onto the app
    /// bundle as a Finder custom icon, so it survives quitting the app.
    static func apply() {
        let bundlePath = Bundle.main.bundlePath
        if UserDefaults.standard.string(forKey: "orbit:app-icon") == "light",
           let light = NSImage(named: "AppIconLight") {
            NSApp.applicationIconImage = light
            // setIcon needs a concrete bitmap; asset-catalog images are lazy proxies
            if let tiff = light.tiffRepresentation, let concrete = NSImage(data: tiff) {
                NSWorkspace.shared.setIcon(concrete, forFile: bundlePath)
            }
        } else {
            NSApp.applicationIconImage = nil
            NSWorkspace.shared.setIcon(nil, forFile: bundlePath)
        }
    }
}

enum OrbitWindow {
    /// SwiftUI opens a fixed, roughly half-screen window. Fill the screen
    /// instead — `visibleFrame` keeps clear of the menu bar and the Dock.
    static func fillScreen() {
        DispatchQueue.main.async {
            guard let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }),
                  let screen = window.screen ?? NSScreen.main else { return }
            window.setFrame(screen.visibleFrame, display: true)
        }
    }
}

@main
struct OrbitApp: App {
    private let container: ModelContainer = {
        let schema = Schema([
            Workspace.self,
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
                .frame(minWidth: 420, minHeight: 420)
                .onAppear {
                    OrbitAppIcon.apply()
                    OrbitWindow.fillScreen()
                }
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
    /// Posted by the topbar breadcrumb; whichever screen has a page open closes
    /// it and returns to its list.
    static let closeOpenPage = Notification.Name("orbit.close-open-page")
}
