import Foundation
import LocalAuthentication

/// Touch ID gating for workspaces, in the spirit of Apple Notes' locked notes.
///
/// **What this protects:** someone picking up your unlocked Mac, or looking over
/// your shoulder while you share a screen. It hides the workspace behind an
/// authentication prompt.
///
/// **What it does not protect:** the notes themselves. The store is a plain
/// SQLite file, so anyone able to read it can see locked content without ever
/// launching Orbit. Encrypting it instead would mean a forgotten secret
/// destroys the notes for good, which is the wrong trade for irreplaceable data.
@MainActor
final class WorkspaceLock: ObservableObject {
    /// Deliberately in memory only — never persisted. That is what makes every
    /// launch start locked again, with no "relock on quit" bookkeeping to get
    /// wrong, and nothing useful left behind if the app crashes.
    @Published private var unlockedIDs: Set<UUID> = []

    /// Set while a prompt is on screen, so the gate can't spawn a second one.
    @Published private(set) var isAuthenticating = false

    /// Shown on the gate when authentication fails or is unavailable.
    @Published var failureMessage: String?

    func isUnlocked(_ id: UUID) -> Bool { unlockedIDs.contains(id) }

    /// True when this workspace should be hidden behind the gate right now.
    func isBlocked(_ workspace: Workspace?) -> Bool {
        guard let workspace, workspace.locked else { return false }
        return !isUnlocked(workspace.id)
    }

    func lock(_ id: UUID) { unlockedIDs.remove(id) }

    func lockAll() { unlockedIDs.removeAll() }

    /// Biometrics with the Mac login password as fallback, so a failed or
    /// missing sensor never leaves the workspace unreachable.
    func unlock(_ workspace: Workspace) async -> Bool {
        guard !isAuthenticating else { return false }
        guard workspace.locked else { return true }

        let context = LAContext()
        context.localizedFallbackTitle = "Use Password…"

        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            failureMessage = "This Mac cannot authenticate right now."
            return false
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        let reason = "unlock the “\(workspace.name)” workspace"
        let granted: Bool = await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }

        if granted {
            unlockedIDs.insert(workspace.id)
            failureMessage = nil
        } else {
            failureMessage = "Authentication was cancelled."
        }
        return granted
    }
}
