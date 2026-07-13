import Foundation

enum TaskCompletionService {
    @MainActor
    static func recompute(task: OrbitTask, steps: [OrbitTaskStep]) {
        let children = Dictionary(grouping: steps, by: \.parentID)
        var cache: [UUID: Bool] = [:]

        func complete(_ step: OrbitTaskStep) -> Bool {
            if let cached = cache[step.id] { return cached }
            let childSteps = children[step.id] ?? []
            let value = childSteps.isEmpty ? step.done : childSteps.allSatisfy(complete)
            cache[step.id] = value
            if !childSteps.isEmpty { step.done = value }
            return value
        }

        let roots = children[nil] ?? []
        let newDone = !roots.isEmpty && roots.allSatisfy(complete)
        if newDone && !task.done { task.completedAt = .now }
        if !newDone { task.completedAt = nil }
        task.done = newDone
    }
}

