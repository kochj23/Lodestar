import Foundation
import AVFoundation

/// Zero-dependency, fully on-device TTS using the system speech synthesizer.
/// Good enough to talk back today; swap in Piper or Nova's F5-TTS for nicer voices.
final class AVSpeechTTS: NSObject, TTSProvider {
    private let synth = AVSpeechSynthesizer()

    func speak(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let u = AVSpeechUtterance(string: t)
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        u.prefersAssistiveTechnologySettings = false
        synth.speak(u)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }
}
