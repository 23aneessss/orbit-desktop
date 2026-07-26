import SwiftUI

/// How much room the window currently gives us.
///
/// Orbit is a desktop app people park beside other windows, so every screen has
/// to survive being squeezed to roughly a third of the display. Views read this
/// from the environment instead of each embedding its own `GeometryReader`.
enum OrbitWidthClass: Int, Comparable {
    /// Narrow enough that the sidebar has to get out of the way entirely.
    case compact
    /// Sidebar collapses to an icon rail, secondary columns start dropping.
    case medium
    case regular

    init(_ width: CGFloat) {
        switch width {
        case ..<640: self = .compact
        case ..<960: self = .medium
        default: self = .regular
        }
    }

    static func < (lhs: OrbitWidthClass, rhs: OrbitWidthClass) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var isCompact: Bool { self == .compact }

    /// Outer padding for list and dashboard screens.
    var pagePadding: CGFloat {
        switch self {
        case .compact: 16
        case .medium: 24
        case .regular: 32
        }
    }

    /// Horizontal padding for the document reader, which needs more air than a
    /// list when there is room and much less when there is not.
    var readerPadding: CGFloat {
        switch self {
        case .compact: 14
        case .medium: 32
        case .regular: 54
        }
    }

    /// The block editor's hover gutter. Still usable when narrow, just tighter.
    var gutterWidth: CGFloat {
        isCompact ? 26 : 42
    }

    /// Section headers stack their controls under the title once the row would
    /// otherwise overflow.
    var stacksSectionHeaders: Bool { self == .compact }
}

private struct OrbitWidthClassKey: EnvironmentKey {
    static let defaultValue = OrbitWidthClass.regular
}

extension EnvironmentValues {
    var orbitWidth: OrbitWidthClass {
        get { self[OrbitWidthClassKey.self] }
        set { self[OrbitWidthClassKey.self] = newValue }
    }
}
