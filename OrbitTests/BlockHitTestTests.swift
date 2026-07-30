import XCTest
@testable import Orbit

/// Window coordinates put the origin bottom-left, so the *first* block of a
/// document has the *largest* y. Getting that backwards made an upward drag
/// select downwards, which is what these cases pin down.
final class BlockHitTestTests: XCTestCase {
    private let top = UUID()
    private let middle = UUID()
    private let bottom = UUID()

    /// Three rows, 20pt tall, with a 10pt gap between each.
    private var frames: [(id: UUID, rect: NSRect)] {
        [
            (top, NSRect(x: 0, y: 200, width: 100, height: 20)),     // 200...220
            (middle, NSRect(x: 0, y: 170, width: 100, height: 20)),  // 170...190
            (bottom, NSRect(x: 0, y: 140, width: 100, height: 20))   // 140...160
        ]
    }

    func testResolvesBlockContainingTheY() {
        XCTAssertEqual(BlockHitTest.blockID(atY: 210, in: frames), top)
        XCTAssertEqual(BlockHitTest.blockID(atY: 180, in: frames), middle)
        XCTAssertEqual(BlockHitTest.blockID(atY: 150, in: frames), bottom)
    }

    func testGapBetweenRowsSnapsToTheNearestBlockNotTheWrongEnd() {
        // Gap 190...200: nearer edge wins, so it never jumps to the far end.
        XCTAssertEqual(BlockHitTest.blockID(atY: 192, in: frames), middle)
        XCTAssertEqual(BlockHitTest.blockID(atY: 198, in: frames), top)
    }

    func testDraggingPastEitherEndClampsInsteadOfInverting() {
        XCTAssertEqual(BlockHitTest.blockID(atY: 900, in: frames), top)     // dragged up, off the page
        XCTAssertEqual(BlockHitTest.blockID(atY: -900, in: frames), bottom) // dragged down, off the page
    }

    func testNoFramesResolvesToNothing() {
        XCTAssertNil(BlockHitTest.blockID(atY: 100, in: []))
    }
}
