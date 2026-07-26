import Foundation

enum IdeaHierarchy {
    /// Every ancestor of `idea`, ordered root first, for the page breadcrumb.
    ///
    /// `parentID` is a plain UUID rather than a SwiftData relationship, so
    /// nothing at the storage layer prevents a cycle (a restored backup or a
    /// merge could produce one). The `seen` set makes a corrupt chain terminate
    /// instead of hanging the editor.
    static func ancestors(of idea: Idea, in all: [Idea]) -> [Idea] {
        var byID: [UUID: Idea] = [:]
        for candidate in all { byID[candidate.id] = candidate }

        var chain: [Idea] = []
        var seen: Set<UUID> = [idea.id]
        var cursor = idea.parentID

        while let parentID = cursor, !seen.contains(parentID), let parent = byID[parentID] {
            chain.append(parent)
            seen.insert(parentID)
            cursor = parent.parentID
        }

        return chain.reversed()
    }

    /// How deep a page sits below its root.
    static func depth(of idea: Idea, in all: [Idea]) -> Int {
        ancestors(of: idea, in: all).count
    }
}
