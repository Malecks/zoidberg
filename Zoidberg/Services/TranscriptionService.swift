// Zoidberg/Services/TranscriptionService.swift
import Speech
import AVFoundation

protocol TranscriptionDelegate: AnyObject {
    func transcriptionDidUpdate(text: String)
    func transcriptionDidFinish(finalText: String)
    func transcriptionDidFail(error: Error)
    func transcriptionAudioLevel(_ level: Float)
}

protocol TranscriptionProvider {
    var isListening: Bool { get }
    var delegate: TranscriptionDelegate? { get set }
    func startListening() throws
    func stopListening()
}

final class MacOSDictationService: NSObject, TranscriptionProvider {
    weak var delegate: TranscriptionDelegate?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var lastLevelTime: CFAbsoluteTime = 0

    private(set) var isListening = false

    func startListening() throws {
        guard Permissions.checkSpeechRecognition() == .granted else {
            throw TranscriptionError.permissionDenied
        }

        // Clean up any previous session without triggering cancel errors
        if isListening {
            cleanupAudio()
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        let inputNode = audioEngine.inputNode

        // Use the native format from the input node — avoids sample rate mismatches
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            throw TranscriptionError.setupFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            // Calculate RMS audio level, throttled to ~30fps
            guard let self = self else { return }
            let now = CFAbsoluteTimeGetCurrent()
            guard now - self.lastLevelTime > 0.016 else { return }
            self.lastLevelTime = now

            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(frameLength))
            // Gate out background noise, then scale with a curve for more range
            let gated = rms < 0.0015 ? Float(0) : rms
            let scaled = sqrt(min(1.0, gated * 25)) // sqrt curve gives more midrange
            let level = scaled
            self.delegate?.transcriptionAudioLevel(level)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    self.delegate?.transcriptionDidFinish(finalText: text)
                    self.cleanupAudio()
                } else {
                    self.delegate?.transcriptionDidUpdate(text: text)
                }
            }

            if let error = error as? NSError {
                // Code 301 = user canceled, not a real error
                if error.domain == "kLSRErrorDomain" && error.code == 301 {
                    return
                }
                self.delegate?.transcriptionDidFail(error: error)
                self.cleanupAudio()
            }
        }
    }

    func stopListening() {
        // End the audio stream gracefully so the recognizer can finalize
        recognitionRequest?.endAudio()

        // Give the recognizer a moment to produce a final result,
        // then clean up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.cleanupAudio()
        }
    }

    private func cleanupAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }
}

enum TranscriptionError: Error {
    case permissionDenied
    case setupFailed
}
