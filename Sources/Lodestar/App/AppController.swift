import AppKit

/// Wires everything together and runs a "turn": perceive → infer → answer (speak) →
/// optionally point. Nothing here is provider-specific; swapping Nova for Ollama is a
/// config change.
@MainActor
final class AppController: NSObject {
    private var config: Config
    private var egress: EgressGuard
    private var registry: ProviderRegistry
    private let tts: TTSProvider
    private var speakEnabled: Bool

    private let menu = MenuBarController()
    private let hud = HUDController()
    private let overlay = PointerOverlay()
    private let settings = SettingsController()
    private var hotkey: HotkeyManager

    private var lastElements: [AXElement] = []
    private var paused = false

    override init() {
        config = Config.loadOrCreate()
        egress = EgressGuard(allowlist: config.security.egressAllowlist,
                             allowPrivateNetwork: config.security.allowPrivateNetwork ?? true)
        registry = ProviderRegistry(config: config, egress: egress)
        tts = AVSpeechTTS()   // swap for Piper/F5 provider when configured
        speakEnabled = config.speech.tts != "none"
        hotkey = HotkeyManager(invoke: config.hotkey.invoke)
        super.init()
    }

    func start() {
        menu.install(providerIDs: registry.ids, egressSummary: egress.summary)
        menu.onAskScreen = { [weak self] in self?.invoke() }
        menu.onTogglePause = { [weak self] in
            guard let self else { return }
            self.paused = self.menu.paused
            if self.paused { self.tts.stop(); self.overlay.hide() }
        }
        hud.model.onSubmit = { [weak self] text in self?.ask(text) }
        hotkey.onInvoke = { [weak self] in self?.invoke() }
        hotkey.start()

        menu.onSettings = { [weak self] in
            guard let self else { return }
            self.settings.show(config: self.config)
        }
        settings.onSave = { [weak self] cfg in self?.reload(cfg) }

        if !Accessibility.isTrusted {
            Log.warn("Accessibility not granted — the hotkey won't work until you enable "
                   + "Lodestar in System Settings › Privacy & Security › Accessibility.")
            Accessibility.promptForTrust()
        }
        Log.info("Lodestar ready · hotkey \(config.hotkey.invoke) · egress: \(egress.summary)")
        showWelcomeIfFirstLaunch()
    }

    private func invoke() {
        guard !paused else { Log.info("privacy pause is on — ignoring invoke"); return }
        hud.showAtCursor()
    }

    /// Menu-bar apps have no window or dock icon, so the first launch can look like
    /// "nothing happened". Show a one-time note (keyed on a marker file) telling the
    /// user it's alive, where it lives, and how to use it.
    private func showWelcomeIfFirstLaunch() {
        let marker = Config.path.deletingLastPathComponent().appendingPathComponent(".welcomed")
        if FileManager.default.fileExists(atPath: marker.path) { return }
        try? FileManager.default.createDirectory(
            at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: marker.path, contents: nil)

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Lodestar is running"
        alert.informativeText = """
        Lodestar lives in your menu bar — look for the cursor icon at the top-right \
        (if your menu bar is full, it may be tucked behind the notch). There is no dock \
        icon or main window by design.

        To use the \(config.hotkey.invoke) hotkey, enable Lodestar in System Settings › \
        Privacy & Security › Accessibility (you should have just been prompted). You can \
        also click the menu-bar icon → "Ask about screen" any time.
        """
        alert.addButton(withTitle: "Got it")
        alert.addButton(withTitle: "Open Settings…")
        if alert.runModal() == .alertSecondButtonReturn {
            settings.show(config: config)
        }
    }

    /// Persist a config edited in the Settings window and apply it live — no restart.
    private func reload(_ newConfig: Config) {
        do { try newConfig.save() } catch { Log.warn("could not write config: \(error)") }
        config = newConfig
        egress = EgressGuard(allowlist: newConfig.security.egressAllowlist,
                             allowPrivateNetwork: newConfig.security.allowPrivateNetwork ?? true)
        registry = ProviderRegistry(config: newConfig, egress: egress)
        speakEnabled = newConfig.speech.tts != "none"

        hotkey.stop()
        hotkey = HotkeyManager(invoke: newConfig.hotkey.invoke)
        hotkey.onInvoke = { [weak self] in self?.invoke() }
        hotkey.start()

        menu.install(providerIDs: registry.ids, egressSummary: egress.summary)
        Log.info("settings applied · hotkey \(newConfig.hotkey.invoke) · egress: \(egress.summary)")
    }

    private func ask(_ text: String) {
        guard !paused else { return }
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "What's on my screen right now? Be brief."
            : text
        hud.model.busy = true
        hud.model.answer = ""
        Task { await runTurn(question) }
    }

    private func runTurn(_ question: String) async {
        // 1) Perceive. Only grab pixels if a vision-capable provider will use them.
        let visionRoute = registry.route(.vision)
        let wantsVision = visionRoute?.capabilities.contains(.vision) ?? false
        let ctx = await ContextFuser.build(includeScreenshot: wantsVision)
        lastElements = ctx.elements

        // 2) Choose provider.
        let provider: InferenceProvider?
        var images: [Attachment] = []
        if let shot = ctx.screenshot, let v = visionRoute, v.capabilities.contains(.vision) {
            provider = v
            images = [Attachment(pngData: shot)]
        } else {
            provider = registry.route(.default)
        }
        guard let provider else {
            hud.model.answer = "No provider configured. Edit ~/.config/lodestar/config.json."
            hud.model.busy = false
            return
        }

        // 3) Build the conversation.
        let messages = [
            Message(.system, AssistantIntent.systemPrompt),
            Message(.user, ContextFuser.promptText(ctx) + "\nUser: " + question, images: images),
        ]

        // 4) Stream the answer into the HUD.
        var full = ""
        do {
            for try await chunk in provider.chat(ChatRequest(messages: messages)) {
                full += chunk.textDelta
                hud.model.answer = full
            }
        } catch {
            hud.model.answer = "⚠️ \(error)"
            hud.model.busy = false
            return
        }
        hud.model.busy = false

        // 5) Intent → speak, and point if there's a concrete target on screen.
        let intent = AssistantIntent.parse(full)
        hud.model.answer = intent.say.isEmpty ? full : intent.say
        if speakEnabled { tts.speak(hud.model.answer) }
        if let target = intent.pointTarget,
           let rect = Targeter.resolve(target, in: lastElements) {
            overlay.point(atAX: rect)
        }
    }
}
