import Foundation

/// Headless one-shot: `Lodestar ask "<question>" [provider]`. Runs the real provider
/// pipeline (same code the GUI uses) and prints the answer — so the inference path can
/// be tested end-to-end from the terminal, no clicking required.
enum CLI {
    static func run(_ args: [String]) -> Bool {
        guard args.count >= 2, args[0] == "ask" else { return false }
        let providerOverride = args.count >= 3 ? args.last : nil
        let question = (providerOverride == nil ? args[1...] : args[1..<(args.count - 1)])
            .joined(separator: " ")

        let sem = DispatchSemaphore(value: 0)
        Task {
            await ask(question, provider: providerOverride)
            sem.signal()
        }
        sem.wait()
        return true
    }

    private static func ask(_ question: String, provider providerID: String?) async {
        var config = Config.loadOrCreate()
        config = ModelResolver.resolve(config)
        let egress = EgressGuard(allowlist: config.security.egressAllowlist,
                                 allowPrivateNetwork: config.security.allowPrivateNetwork ?? true)
        let registry = ProviderRegistry(config: config, egress: egress)

        let provider = providerID.flatMap { registry.provider($0) } ?? registry.route(.default)
        guard let provider else { print("no provider available"); return }
        FileHandle.standardError.write(Data("(using provider: \(provider.id))\n".utf8))

        let messages = [
            Message(.system, AssistantIntent.systemPrompt),
            Message(.user, question),
        ]
        do {
            var full = ""
            for try await chunk in provider.chat(ChatRequest(messages: messages)) {
                full += chunk.textDelta
                FileHandle.standardOutput.write(Data(chunk.textDelta.utf8))
            }
            if full.isEmpty { print("\n(no output)") } else { print("") }
        } catch {
            print("ERROR: \(error)")
        }
    }
}
