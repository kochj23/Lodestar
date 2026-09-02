import AppKit

/// Wires everything together and runs a "turn": perceive → infer → answer (speak) →
/// optionally point. Nothing here is provider-specific; swapping Nova for Ollama is a
/// config change.
@MainActor
final class AppController: NSObject {
    private let config: Config
    private let egress: EgressGuard
    private let registry: ProviderRegistry
    private let tts: TTSProvider

    private let menu = MenuBarController()
    private let hud = HUDController()
    private let overlay = PointerOverlay()
    private let hotkey: HotkeyManager

    private var lastElements: [AXElement] = []
    private var paused = false

    override init() {
        config = Config.loadOrCreate()
        egress = EgressGuard(allowlist: config.security.egressAllowlist)
        registry = ProviderRegistry(config: config, egress: egress)
        tts = AVSpeechTTS()   // swap for Piper/F5 provider when configured
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

        if !Accessibility.isTrusted {
            Log.warn("Accessibility not granted — hotkey, context reading and pointing will be "
                   + "limited. Grant it in System Settings › Privacy & Security › Accessibility.")
        }
        Log.info("Lodestar ready · hotkey \(config.hotkey.invoke) · egress: \(egress.summary)")
    }

    private func invoke() {
        guard !paused else { Log.info("privacy pause is on — ignoring invoke"); return }
        hud.showAtCursor()
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
        tts.speak(hud.model.answer)
        if let target = intent.pointTarget,
           let rect = Targeter.resolve(target, in: lastElements) {
            overlay.point(atAX: rect)
        }
    }
}
