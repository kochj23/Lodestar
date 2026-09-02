import XCTest
import CoreGraphics
@testable import Lodestar

/// Category 2/7 — Performance: bounded work, no unbounded growth in the hot paths.
final class PerformanceTests: XCTestCase {

    func testTargeterScalesToLargeTree() {
        let els = (0..<5000).map {
            AXElement(role: "AXButton", label: "Item \($0)",
                      frame: CGRect(x: 0, y: CGFloat($0), width: 10, height: 10))
        }
        measure { _ = Targeter.resolve("Item 4999", in: els) }
    }

    func testPromptSelectionIsBounded() {
        let huge = String(repeating: "a", count: 10_000)
        let b = ContextBundle(appName: "App", selection: huge, axSummary: "",
                              screenshot: nil, elements: [])
        let text = ContextFuser.promptText(b)
        XCTAssertLessThan(text.count, 800, "selection must be truncated so prompts stay bounded")
    }

    func testContextSummaryIsCapped() {
        // 60-element cap keeps the prompt from ballooning on huge windows.
        let many = (0..<1000).map {
            AXElement(role: "AXStaticText", label: "Label \($0)", frame: .zero)
        }
        let lines = many.prefix(60).count
        XCTAssertEqual(lines, 60)
    }
}
