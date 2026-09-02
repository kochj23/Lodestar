import XCTest
@testable import Lodestar

/// Covers the Settings window's model — the thing that replaces hand-editing JSON.
/// Touches Unit (populate/apply), Functional (edit → new config end-to-end), and Frame
/// (controller constructs). @MainActor because it drives @Published UI state.
@MainActor
final class SettingsTests: XCTestCase {

    func testModelPopulatesFromConfig() {   // Unit
        let m = SettingsModel(config: .default)
        XCTAssertEqual(m.routeDefault, "nova")
        XCTAssertEqual(m.novaPreferredBackend, "ollama")
        XCTAssertTrue(m.providerIDs.contains("ollama"))
        XCTAssertFalse(m.allowlistText.isEmpty)
    }

    func testMakeConfigAppliesEdits() {     // Functional — golden path of the whole feature
        let m = SettingsModel(config: .default)
        m.routeDefault = "ollama"
        m.hotkeyInvoke = "cmd+shift+l"
        m.novaPreferredBackend = ""          // "let the balancer choose"
        m.allowPrivateNetwork = false
        m.ttsEngine = "none"
        m.allowlistText = "a.local, b.digitalnoise.net"
        if let i = m.providerRows.firstIndex(where: { $0.id == "ollama" }) {
            m.providerRows[i].baseUrl = "http://127.0.0.1:9999/v1"
            m.providerRows[i].text = "qwen2.5:14b"
        }

        let c = m.makeConfig()
        XCTAssertEqual(c.routing.default, "ollama")
        XCTAssertEqual(c.hotkey.invoke, "cmd+shift+l")
        XCTAssertNil(c.providers["nova"]?.preferredBackend)   // "" → nil
        XCTAssertEqual(c.security.allowPrivateNetwork, false)
        XCTAssertEqual(c.speech.tts, "none")
        XCTAssertEqual(c.security.egressAllowlist, ["a.local", "b.digitalnoise.net"])
        XCTAssertEqual(c.providers["ollama"]?.baseUrl, "http://127.0.0.1:9999/v1")
        XCTAssertEqual(c.providers["ollama"]?.text, "qwen2.5:14b")
    }

    func testMakeConfigPreservesUntouchedFields() {   // Unit — no data loss
        let c = SettingsModel(config: .default).makeConfig()
        XCTAssertEqual(c.providers["nova"]?.path, Config.default.providers["nova"]?.path)
        XCTAssertEqual(c.providers["nova"]?.responseKey, Config.default.providers["nova"]?.responseKey)
    }

    func testSettingsControllerConstructs() {   // Frame — smoke
        _ = SettingsController()
    }
}
