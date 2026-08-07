import SwiftUI

/// Stands in for a locked workspace's content until Touch ID succeeds.
///
/// It shows the workspace's name and icon but nothing from inside it — the point
/// is that a glance at the screen reveals no note titles.
struct WorkspaceLockScreen: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lock: WorkspaceLock
    let workspace: Workspace

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(OrbitTheme.sunken(scheme))
                    .frame(width: 74, height: 74)
                Image(systemName: "lock.fill")
                    .font(.system(size: 27))
                    .foregroundStyle(OrbitTheme.ink2(scheme))
            }

            VStack(spacing: 6) {
                Text("\(workspace.icon)  \(workspace.name)")
                    .font(.system(size: 17, weight: .semibold))
                Text("This workspace is locked.")
                    .font(.system(size: 13))
                    .foregroundStyle(OrbitTheme.ink2(scheme))
            }

            Button {
                Task { await lock.unlock(workspace) }
            } label: {
                Label("Unlock with Touch ID", systemImage: "touchid")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 18).frame(height: 38)
            }
            .buttonStyle(.borderedProminent)
            .tint(OrbitTheme.accent)
            .disabled(lock.isAuthenticating)

            if let message = lock.failureMessage {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(OrbitTheme.ink3(scheme))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OrbitTheme.canvas(scheme))
        // Prompt straight away, so opening a locked workspace is one gesture and
        // the button is only there for a retry.
        .task(id: workspace.id) {
            guard !lock.isUnlocked(workspace.id) else { return }
            _ = await lock.unlock(workspace)
        }
    }
}
