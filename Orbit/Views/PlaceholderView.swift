import SwiftUI

struct PlaceholderView: View {
    @Environment(\.colorScheme) private var scheme
    let section: OrbitSection
    let message: String

    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: section.symbol)
                .font(.system(size: 24))
                .foregroundStyle(OrbitTheme.accent)
                .frame(width: 52, height: 52)
                .background(OrbitTheme.accentSoft(scheme), in: RoundedRectangle(cornerRadius: 14))
            Text(section.rawValue).font(.system(size: 22, weight: .semibold))
            Text(message)
                .font(.system(size: 13.5))
                .foregroundStyle(OrbitTheme.ink2(scheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OrbitTheme.canvas(scheme))
    }
}
