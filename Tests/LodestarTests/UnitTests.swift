import XCTest
import AppKit
import CoreGraphics
@testable import Lodestar

/// Category 4/7 — Unit: individual functions in isolation, edge cases.
final class UnitTests: XCTestCase {

    func testHotkeyParse() {
        let c = HotkeyManager.parse("ctrl+opt+space")
        XCTAssertTrue(c.mods.contains(.control))
        XCTAssertTrue(c.mods.contains(.option))
        XCTAssertFalse(c.mods.contains(.command))
        XCTAssertEqual(c.key, "space")

        let l = HotkeyManager.parse("cmd+shift+k")
        XCTAssertTrue(l.mods.contains(.command))
        XCTAssertTrue(l.mods.contains(.shift))
        XCTAssertEqual(l.key, "k")
    }

    func testIntentParseWithFence() {
        let raw = "Sure.\n```lodestar\n{\"say\":\"Click Export.\",\"point\":\"Export button\"}\n```"
        let i = AssistantIntent.parse(raw)
        XCTAssertEqual(i.say, "Click Export.")
        XCTAssertEqual(i.pointTarget, "Export button")
    }

    func testIntentParseNoFence() {
        let i = AssistantIntent.parse("Just a plain answer.")
        XCTAssertEqual(i.say, "Just a plain answer.")
        XCTAssertNil(i.pointTarget)
    }

    func testIntentParseMalformedFenceFallsBack() {
        let raw = "Hi\n```lodestar\n{not valid json}\n```"
        let i = AssistantIntent.parse(raw)
        XCTAssertNil(i.pointTarget)
        XCTAssertFalse(i.say.isEmpty)
    }

    func testAxToCocoaFlipsY() {
        let ax = CGRect(x: 100, y: 50, width: 40, height: 20)   // 50px from top
        let cocoa = PointerOverlay.axToCocoa(ax, primaryHeight: 1000)
        XCTAssertEqual(cocoa.origin.x, 100)
        XCTAssertEqual(cocoa.origin.y, 930)   // 1000 - 50 - 20
        XCTAssertEqual(cocoa.height, 20)
    }

    func testOpenAIBodyShape() throws {
        let req = ChatRequest(messages: [Message(.system, "s"), Message(.user, "hi")], stream: true)
        let data = try OpenAICompatibleProvider.makeBody(model: "m", req: req)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["model"] as? String, "m")
        XCTAssertEqual(obj["stream"] as? Bool, true)
        let msgs = try XCTUnwrap(obj["messages"] as? [[String: Any]])
        XCTAssertEqual(msgs.count, 2)
        XCTAssertEqual(msgs.first?["role"] as? String, "system")
    }

    func testConfigCodableRoundTrip() throws {
        let enc = JSONEncoder(); enc.keyEncodingStrategy = .convertToSnakeCase
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        let data = try enc.encode(Config.default)
        let back = try dec.decode(Config.self, from: data)
        XCTAssertEqual(back.providers.count, Config.default.providers.count)
        XCTAssertEqual(back.routing.default, Config.default.routing.default)
        XCTAssertEqual(back.hotkey.invoke, Config.default.hotkey.invoke)
    }

    func testTargeterFuzzyMatch() {
        let els = [AXElement(role: "AXButton", label: "Export as PDF…",
                             frame: CGRect(x: 10, y: 10, width: 50, height: 20))]
        XCTAssertNotNil(Targeter.resolve("the export button", in: els))
        XCTAssertNil(Targeter.resolve("something unrelated", in: els))
    }
}
