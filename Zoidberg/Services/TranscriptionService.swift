// Zoidberg/Services/TranscriptionService.swift
import Speech
import AVFoundation

protocol TranscriptionDelegate: AnyObject {
    func transcriptionDidUpdate(text: String)
    func transcriptionDidFinish(finalText: String)
    func transcriptionDidFail(error: Error)
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

    private(set) var isListening = false

    func startListening() throws {
        guard Permissions.checkSpeechRecognition() == .granted else {
            throw TranscriptionError.permissionDenied
        }
        stopListening()

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            throw TranscriptionError.setupFailed
        }
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
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
                    self.stopListening()
                } else {
                    self.delegate?.transcriptionDidUpdate(text: text)
                }
            }
            if let error = error {
                self.delegate?.transcriptionDidFail(error: error)
                self.stopListening()
            }
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
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
