import Foundation

/// Speech is two more swappable capabilities, exactly like text/vision.
protocol TTSProvider: AnyObject {
    func speak(_ text: String)
    func stop()
}

protocol STTProvider: AnyObject {
    /// 16-bit PCM mono. Returns the transcript.
    func transcribe(_ pcm: Data) async throws -> String
}

/// Default STT until a real engine is wired (WhisperKit / whisper.cpp / MLX-Whisper).
/// It fails loudly rather than pretending — voice-in is opt-in.
final class NullSTT: STTProvider {
    func transcribe(_ pcm: Data) async throws -> String {
        throw ProviderError.notConfigured(
            "no STT engine set (speech.stt). Wire WhisperKit/whisper.cpp to enable voice input.")
    }
}
