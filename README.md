# Lodestar

**A local-only AI companion that lives next to your mouse cursor on macOS.** Hit a
hotkey and a small bubble appears at your pointer: it reads what's on your screen,
answers out loud, and can physically point at the control you're looking for — all
driven by *your own* models on your machine or LAN. Lodestar itself **never talks to the
public internet** — only to endpoints you run.

---

## Where this came from, and what it's for

Lodestar is an independent, **local-only reimagining of [Clicky](https://www.producthunt.com/products/clicky-2)**
— the delightful "AI buddy that lives next to your cursor on Mac"
([XDA writeup](https://www.xda-developers.com/someone-built-tiny-ai-that-lives-next-to-your-cursor-the-most-useful-thing-ive-tried-this-year/),
[clickyhq.com](https://www.clickyhq.com/)). Full credit to Clicky's creator for the idea
and the interaction design; the cursor-adjacent, screen-aware, *points-at-things* UX is
theirs.

The one thing Lodestar changes is the thing that matters most for a tool that watches your
screen and listens to your mic: **where your data goes.** Clicky is powered by cloud
services (Claude, AssemblyAI, ElevenLabs), so your screen and voice leave your machine.
Lodestar is built the other way around.

### Goals (the non-negotiables)

1. **Local-network-only, enforced — not promised.** Every network request passes through a
   single egress chokepoint that permits loopback, private-LAN addresses (RFC1918 / `.local`),
   and hosts you name — and denies the public internet outright. So screen and audio can only
   reach a model on your own machine or LAN. (Flip `allow_private_network: false` for
   loopback-only "strictly local" mode.)
2. **Provider-agnostic, including Nova.** Lodestar ships no model. Text, vision, speech-to-
   text and text-to-speech are each a swappable capability. Ollama, LM Studio, llama.cpp,
   vLLM, MLX, and the **Nova Gateway** are all first-class behind one small interface.
3. **Native and small.** Swift + system frameworks, zero external dependencies, so it
   builds offline and stays auditable.
4. **Privacy by construction.** Secure-field redaction before any screenshot is sent, a
   visible capture state, a privacy pause, ephemeral (never-persisted) capture, and any
   provider token kept in the Keychain.
5. **Intelligence ≠ grounding.** The model only ever emits *intent* ("point at the Export
   button"); a local Targeter resolves that to real on-screen coordinates via the
   Accessibility tree. That's what lets pointing work with *any* local model, however small.

---

## How it works

```mermaid
flowchart TB
  HK["Hotkey (⌃⌥Space)"] --> PERC
  subgraph PERC["Perceive (local)"]
    AX["Accessibility tree<br/>(controls + frames)"]
    CAP["ScreenCaptureKit<br/>(only if vision route)"]
    SEL["selection · focused app"]
  end
  PERC --> FUSE["ContextBundle<br/>(in-memory, never stored)"]
  FUSE --> ROUTE{Router}
  ROUTE -->|text| P1["OpenAICompatibleProvider<br/>Ollama · LM Studio · llama.cpp · MLX"]
  ROUTE -->|persona+memory| P2["NovaGatewayProvider<br/>127.0.0.1:18792"]
  P1 --> EG[[EgressGuard<br/>allow-list + retry]]
  P2 --> EG
  EG --> OUT["streamed answer"]
  OUT --> HUD["Cursor HUD"]
  OUT --> TTS["local TTS (AVSpeech / Piper / F5)"]
  OUT --> INT["AssistantIntent.parse"]
  INT -->|point target| TGT["Targeter<br/>(intent → on-screen rect, local)"]
  TGT --> OVL["Pointer overlay<br/>(click-through, multi-monitor)"]
```

The model speaks; grounding stays local. Swapping Nova for a 3B Ollama model is a config
change and pointing still works.

---

## Build & run

Requires macOS 14+ and a Swift 5.9+ toolchain.

```sh
swift build            # zero dependencies — builds offline
swift test             # 33 tests across all 7 categories
swift run Lodestar     # runs the menu-bar app
```

For the real thing (so the TCC permission prompts carry proper descriptions), bundle it
into a `.app` using `Bundle/Info.plist` and sign it with your **Apple Development** cert.
Notarization is intentionally **skipped** — this is a personal tool, never headed for the App
Store, so a locally-signed build that runs on your own Macs is all it needs. The app is also
deliberately **not sandboxed** — controlling other apps via Accessibility/AppleScript plus
screen capture is incompatible with the App Sandbox; called out honestly rather than worked
around.

### Permissions it asks for (all explicit macOS grants)

| Permission | Why | If denied |
|---|---|---|
| Accessibility | read UI controls, global hotkey, point at things | hotkey/context/pointing degrade |
| Screen Recording | screenshots for vision models | vision route disabled |
| Microphone | voice input | voice-in disabled |
| Automation (per app) | Notes / Calendar tools | those tools disabled |

---

## How to use

### 1. One-time setup

1. **Have a local model running.** The default expects Ollama:
   ```sh
   ollama serve
   ollama pull llama3.1:8b            # text
   ollama pull llama3.2-vision:11b    # screen vision
   ```
   (Or point the config at MLX / llama.cpp / the Nova gateway — see Configuration.)
2. **Launch Lodestar.** A cursor-rays icon appears in the menu bar; there's no dock icon.
   First launch writes `~/.config/lodestar/config.json`.
3. **Grant permissions** when macOS prompts (or in System Settings › Privacy & Security):
   - **Accessibility** — required for the hotkey, reading on-screen controls, and pointing.
   - **Screen Recording** — for "what's on my screen" (the vision route).
   - **Microphone** — only if you turn on voice input.

   After granting **Accessibility**, quit and relaunch — macOS only applies it on next launch.

### 2. Everyday use

- **Summon it:** press **⌃⌥Space** (Control-Option-Space) anywhere. A bubble pops up next to
  your cursor.
- **Ask:** type a question and hit Return — *"what does this error mean?"*, *"where do I export
  this?"*, *"summarize what I selected."* Leave it blank and press Return to get *"what's on my
  screen right now?"*
- **Answer:** the reply streams into the bubble and is spoken aloud (local TTS).
- **Pointer:** if the answer refers to a specific control, a yellow halo lands on it — across
  monitors.
- **Context is automatic:** the frontmost app, any highlighted text, and (for vision) a
  screenshot are gathered for you each time.

### 3. Menu-bar menu

| Item | What it does |
|---|---|
| **Ask about screen** | Same as the hotkey. |
| **Privacy pause** | Hard-stops all capture + inference. Toggle off to resume. |
| **Egress → …** | Read-only: exactly which hosts the app may contact. |
| **Open config…** | Opens `config.json` in your editor. |
| **Quit Lodestar** | Quits. |

### 4. Point it at a different brain

Edit `~/.config/lodestar/config.json` → `routing`, then relaunch:

- `default` — where **text** questions go (`nova` = Nova's balancer, or `ollama` / `mlx`).
- `vision` — where **screenshots** go (keep a local vision model here).
- `quick` — a small, fast model for lightweight asks.

By default text goes through **Nova** (on your LAN) pinned to a local backend, and screenshots
go to **local Ollama vision** — so nothing reaches the web. See Configuration for the details.

### 5. Troubleshooting

| Symptom | Fix |
|---|---|
| Bubble shows an error / no answer | The routed model isn't reachable. Check `curl 127.0.0.1:11434/api/tags` (Ollama) or `curl 127.0.0.1:18792/health` (Nova). |
| Hotkey does nothing | Grant **Accessibility**, then quit + relaunch. |
| "What's on my screen" is vague | Grant **Screen Recording**, and make sure `routing.vision` points at a vision model (`llama3.2-vision`, `qwen2-vl`). |
| Pointer lands on the wrong control | It matched the wrong element; canvas apps (Figma/DaVinci) have thin Accessibility data and are less precise. |
| `egress blocked` in the log | A provider points at a public host — the app only talks to your machine/LAN by design. Add a LAN host to `security.egress_allowlist` if that's intended. |

---

## Configuration

JSON at `~/.config/lodestar/config.json`, written with sensible local defaults on first
run. You pick which local engine answers what:

```jsonc
{
  "routing": { "default": "nova", "quick": "mlx", "vision": "ollama" },  // Nova balancer (LAN), pinned local
  "providers": {
    "nova":   { "kind": "nova-gateway", "base_url": "http://127.0.0.1:18792",
                "path": "/api/chat", "request_format": "message", "response_key": "response",
                "use_memory": true, "preferred_backend": "ollama", "task_type": "auto" },
    "ollama": { "kind": "openai", "base_url": "http://127.0.0.1:11434/v1",
                "text": "llama3.1:8b", "vision": "llama3.2-vision:11b" }
  },
  "security": {
    "egress_allowlist": ["memory-server.digitalnoise.net", "ollama.digitalnoise.net"],
    "allow_private_network": true,
    "redact_secure_fields": true, "capture_retention": "none"
  }
}
```

Loopback and private-LAN hosts don't need to be listed — `allow_private_network` covers them;
`egress_allowlist` is for *named* LAN hosts. Set `preferred_backend` to keep on-screen text
off the cloud (see Nova mode below).

Provider tokens are **never** put in this file — if a backend needs one it's read from the
Keychain (account `provider-<id>`).

### Nova mode & the built-in load balancer

The default `text` route is already `nova`: Lodestar POSTs to the Nova gateway's
`/api/chat`, which **is** Nova's load balancer — it health-checks and distributes across
`ollama`, `mlx`, `llamacpp` (and `openrouter`) with circuit breakers. You get Nova's
persona and memory for free, and you don't reimplement routing.

Two knobs matter:

- `request_format`: `"message"` → `POST /api/chat {message}` (the running gateway) or
  `"query"` → `POST /api/ai/query {query, task_type, …}` (the richer `nova_gateway` router).
- `preferred_backend`: pin a specific backend, e.g. `"ollama"`.

**Never to the web (the boundary is the internet, not your LAN):** Nova's balancer includes
a *web* backend (`openrouter`, `is_local: false`). Routing through Nova is fine — Nova is on
your LAN — but its cloud backend is not. So the default **pins `preferred_backend` to a local
backend (`ollama`)**, which keeps on-screen text off the web while still going through Nova
for persona + memory. Screenshots always route to local Ollama vision, never Nova. Set
`preferred_backend: null` only if you knowingly want the balancer to be free to pick the web
backend. (Residual: if the pinned local backend is *down*, the gateway may fall back — the
airtight fix would be a local-only route on the gateway, deliberately not added here.)

---

## Tests

Per the project's testing rule, every change carries all **seven** categories, one file
each under `Tests/LodestarTests/`:

`Security` · `Performance` · `Retry` · `Unit` · `Integration` · `Functional` · `Frame`

```sh
swift test
```

---

## Design notes

A fuller design write-up (perception tiers, the vision-grounding fallback, the Nova
adapter, the security model, milestones) lives in [`docs/SPEC.md`](docs/SPEC.md).

## Status

This is v0.1: the full architecture is present and the core loop — perceive → infer →
answer/speak → point — is real and tested. Extension points are marked where a heavier
optional dependency slots in: **WhisperKit** (voice-in), **Piper/F5-TTS** (nicer voices),
and a **vision-grounding fallback** in the Targeter for canvas apps (Figma/DaVinci) where
the Accessibility tree is thin.

## License

MIT © Jordan Koch. Inspired by Clicky; not affiliated with or endorsed by its creator.
