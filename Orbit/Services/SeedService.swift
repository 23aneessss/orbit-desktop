import Foundation
import SwiftData

enum SeedService {
    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: "orbit:demo-data-enabled") else { return }
        let descriptor = FetchDescriptor<Habit>()
        guard (try? context.fetchCount(descriptor)) == 0 else { return }

        let habits = [
            Habit(name: "Deep work", icon: "chevron.left.forwardslash.chevron.right", color: "accent", targetPerWeek: 7),
            Habit(name: "Workout", icon: "figure.strengthtraining.traditional", color: "emerald", targetPerWeek: 4),
            Habit(name: "Read 20 pages", icon: "book.fill", color: "violet", targetPerWeek: 7),
            Habit(name: "Journal", icon: "pencil.line", color: "amber", targetPerWeek: 5)
        ]

        for (habitIndex, habit) in habits.enumerated() {
            context.insert(habit)
            for day in -364...0 {
                let wave = abs((day * 17 + habitIndex * 29) % 100)
                let threshold = [72, 61, 78, 55][habitIndex]
                if wave < threshold {
                    let log = HabitLog(dateKey: OrbitDate.key(OrbitDate.date(daysFromToday: day)), habit: habit)
                    context.insert(log)
                }
            }
        }

        let ideas = [
            Idea(title: "Why personal CRMs fail", content: "Every personal CRM dies the same death: entering data feels like admin work for a job you don't have.", tags: ["orbit", "product"], canvasX: 220, canvasY: 180),
            Idea(title: "People I should talk to more", content: "Noticed my follow-ups cluster around work. The people I actually think about the most are old friends.", tags: ["people", "reflection"], canvasX: 760, canvasY: 145),
            Idea(title: "Consistency beats intensity", content: "The thing about the contribution graph is that it makes absence visible.", tags: ["habits", "psychology"], canvasX: 1160, canvasY: 330),
            Idea(title: "Notes from Atomic Habits", content: "One percent better every day compounds. Make it obvious, attractive, easy and satisfying.", tags: ["books", "habits"], canvasX: 720, canvasY: 500),
            Idea(title: "PIXEL, the mascot concept", content: "A small axolotl-inspired companion that lives in the sidebar. Curious, playful and reliable.", tags: ["orbit", "design"], pinned: true, canvasX: 250, canvasY: 590),
            Idea(title: "App idea: voice memo to note", content: "Record a rambling voice memo on a walk and return to a clean note with tags and actions.", tags: ["ideas", "ai"], canvasX: 770, canvasY: 710)
        ]
        ideas.forEach(context.insert)

        let linkPairs = [(0, 3), (0, 4), (1, 3), (2, 3), (2, 5), (3, 4), (3, 5), (4, 5)]
        for pair in linkPairs {
            context.insert(IdeaLink(ideaAID: ideas[pair.0].id, ideaBID: ideas[pair.1].id))
        }

        context.insert(AppSetting(key: "name", value: "Aness"))
        context.insert(AppSetting(key: "accent", value: "#8b5cf6"))
        context.insert(AppSetting(key: "theme", value: "system"))

        try? context.save()
    }
}
