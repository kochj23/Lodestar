import Foundation

/// Builds providers from config and answers routing questions. This is the piece
/// that lets you keep small models fast (route "quick" at MLX) and heavy things
/// where the big model lives (route "default"/"vision" at Ollama or Nova).
final class ProviderRegistry {
    enum Route { case `default`, quick, vision }

    private var byID: [String: InferenceProvider] = [:]
    private let routing: Config.Routing

    init(config: Config, egress: EgressGuard) {
        self.routing = config.routing
        for (id, pc) in config.providers {
            // Optional per-provider bearer token — Keychain only, never config.
            let token = KeychainStore.get(account: "provider-\(id)")
            switch pc.kind {
            case "openai":
                byID[id] = OpenAICompatibleProvider(
                    id: id, base: pc.baseUrl, textModel: pc.text, visionModel: pc.vision,
                    token: token, egress: egress)
            case "nova-gateway":
                byID[id] = NovaGatewayProvider(
                    id: id, base: pc.baseUrl,
                    path: pc.path ?? "/api/ai/query",
                    responseKey: pc.responseKey ?? "response", token: token, egress: egress)
            default:
                Log.warn("unknown provider kind '\(pc.kind)' for '\(id)' — skipping")
            }
        }
        Log.info("providers: \(byID.keys.sorted().joined(separator: ", "))")
    }

    func provider(_ id: String) -> InferenceProvider? { byID[id] }

    func route(_ r: Route) -> InferenceProvider? {
        let id: String
        switch r {
        case .default: id = routing.default
        case .quick:   id = routing.quick
        case .vision:  id = routing.vision
        }
        return byID[id] ?? byID[routing.default]
    }

    var ids: [String] { byID.keys.sorted() }
}
