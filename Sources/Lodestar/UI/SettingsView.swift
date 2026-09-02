import SwiftUI

/// One editable provider row (base URL + models) for the advanced section.
struct ProviderRow: Identifiable {
    let id: String
    var kind: String
    var baseUrl: String
    var text: String
    var vision: String
}

/// Backs the Settings window. Loads the current Config, exposes editable fields, and
/// produces a new Config on Save — so nobody has to hand-edit JSON.
final class SettingsModel: ObservableObject {
    // General
    @Published var hotkeyInvoke: String
    // Routing
    @Published var routeDefault: String
    @Published var routeQuick: String
    @Published var routeVision: String
    // Nova
    @Published var novaPreferredBackend: String  // "" = let the balancer choose
    @Published var novaRequestFormat: String
    @Published var novaUseMemory: Bool
    // Speech
    @Published var ttsEngine: String
    // Privacy
    @Published var allowPrivateNetwork: Bool
    @Published var redactSecureFields: Bool
    @Published var allowlistText: String          // comma-separated extra hosts
    // Providers (advanced)
    @Published var providerRows: [ProviderRow]

    let providerIDs: [String]
    private let base: Config

    var onSave: ((Config) -> Void)?
    var onCancel: (() -> Void)?

    init(config: Config) {
        base = config
        hotkeyInvoke = config.hotkey.invoke
        routeDefault = config.routing.default
        routeQuick = config.routing.quick
        routeVision = config.routing.vision
        let nova = config.providers["nova"]
        novaPreferredBackend = nova?.preferredBackend ?? ""
        novaRequestFormat = nova?.requestFormat ?? "message"
        novaUseMemory = nova?.useMemory ?? true
        ttsEngine = config.speech.tts
        allowPrivateNetwork = config.security.allowPrivateNetwork ?? true
        redactSecureFields = config.security.redactSecureFields
        allowlistText = config.security.egressAllowlist.joined(separator: ", ")
        providerIDs = config.providers.keys.sorted()
        providerRows = config.providers.keys.sorted().map { id in
            let p = config.providers[id]!
            return ProviderRow(id: id, kind: p.kind, baseUrl: p.baseUrl,
                               text: p.text ?? "", vision: p.vision ?? "")
        }
    }

    /// Apply every edit onto a copy of the loaded Config (untouched fields preserved).
    func makeConfig() -> Config {
        var c = base
        c.hotkey.invoke = hotkeyInvoke
        c.routing = .init(default: routeDefault, quick: routeQuick, vision: routeVision)
        c.speech.tts = ttsEngine
        c.security.allowPrivateNetwork = allowPrivateNetwork
        c.security.redactSecureFields = redactSecureFields
        c.security.egressAllowlist = allowlistText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var providers = c.providers
        for row in providerRows {
            guard var p = providers[row.id] else { continue }
            p.baseUrl = row.baseUrl
            p.text = row.text.isEmpty ? nil : row.text
            p.vision = row.vision.isEmpty ? nil : row.vision
            if row.id == "nova" {
                p.useMemory = novaUseMemory
                p.requestFormat = novaRequestFormat
                p.preferredBackend = novaPreferredBackend.isEmpty ? nil : novaPreferredBackend
            }
            providers[row.id] = p
        }
        c.providers = providers
        return c
    }

    func save()   { onSave?(makeConfig()) }
    func cancel() { onCancel?() }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Hotkey") {
                    TextField("Summon", text: $model.hotkeyInvoke)
                    Text("e.g. ctrl+opt+space").font(.caption).foregroundStyle(.secondary)
                }

                Section("Routing — which model answers what") {
                    routePicker("Text questions", $model.routeDefault)
                    routePicker("Quick asks", $model.routeQuick)
                    routePicker("Screen vision", $model.routeVision)
                }

                Section("Nova") {
                    Picker("Preferred backend", selection: $model.novaPreferredBackend) {
                        Text("balancer chooses (may use web)").tag("")
                        Text("ollama (local)").tag("ollama")
                        Text("mlx (local)").tag("mlx")
                        Text("llamacpp (local)").tag("llamacpp")
                    }
                    Picker("Request format", selection: $model.novaRequestFormat) {
                        Text("message  (/api/chat)").tag("message")
                        Text("query  (/api/ai/query)").tag("query")
                    }
                    Toggle("Use Nova's memory", isOn: $model.novaUseMemory)
                    Text("Pin a local backend to keep on-screen text off the web.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Speech") {
                    Picker("Text-to-speech", selection: $model.ttsEngine) {
                        Text("System voice").tag("avspeech")
                        Text("Off").tag("none")
                    }
                }

                Section("Privacy") {
                    Toggle("Allow private LAN (local-network-only)", isOn: $model.allowPrivateNetwork)
                    Toggle("Redact password fields before capture", isOn: $model.redactSecureFields)
                    TextField("Extra allowed hosts (comma-separated)", text: $model.allowlistText)
                    Text("Loopback + private LAN are always allowed; the public web is always denied.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Providers (advanced)") {
                    ForEach($model.providerRows) { $row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.id).font(.headline)
                            TextField("Base URL", text: $row.baseUrl)
                            if row.kind == "openai" {
                                TextField("Text model", text: $row.text)
                                TextField("Vision model", text: $row.vision)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Text("Saved to ~/.config/lodestar/config.json")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.cancel() }
                Button("Save") { model.save() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 540, height: 620)
    }

    private func routePicker(_ label: String, _ sel: Binding<String>) -> some View {
        Picker(label, selection: sel) {
            ForEach(model.providerIDs, id: \.self) { Text($0).tag($0) }
        }
    }
}
