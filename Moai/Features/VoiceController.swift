import AVFoundation
import Speech
import SwiftUI

@MainActor
final class VoiceController: NSObject, ObservableObject {
    @Published var transcript = ""
    @Published var level: CGFloat = 0
    /// Why nothing was heard, when the answer is a permission or
    /// availability problem rather than silence.
    @Published var failure: String?

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finishCompletion: ((String) -> Void)?
    private var finishTimeout: DispatchWorkItem?
    private var availabilityHint: String?

    func begin() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        transcript = ""
        level = 0
        failure = nil
        finishTimeout?.cancel()
        finishTimeout = nil
        finishCompletion = nil

        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied, .restricted:
            failure = "Speech recognition is off. System Settings, Privacy, Speech Recognition."
            return
        default:
            break
        }
        guard let recognizer else {
            failure = "Speech recognition isn't available on this Mac."
            return
        }
        // isAvailable / supportsOnDeviceRecognition can read false
        // spuriously right after launch while speech assets warm up —
        // never block on them. Record regardless; if recognition then
        // produces nothing, these become the diagnosis.
        availabilityHint = !recognizer.isAvailable
            ? "Speech recognition isn't available right now — try again in a moment."
            : (!recognizer.supportsOnDeviceRecognition
                ? "On-device speech may still be downloading for your language."
                : nil)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            guard let channel = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            var sum: Float = 0
            for index in 0..<frames {
                sum += channel[index] * channel[index]
            }
            let rms = sqrt(sum / Float(frames))
            Task { @MainActor in
                self?.level = CGFloat(min(1, rms * 18))
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            failure = "Mic didn't start. System Settings, Privacy, Microphone."
            audioEngine.inputNode.removeTap(onBus: 0)
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            let text = result.bestTranscription.formattedString
            let isFinal = result.isFinal
            Task { @MainActor in
                guard let self else { return }
                self.transcript = text
                // The final result carries the completed tail of the
                // sentence — deliver on it rather than on a fixed beat,
                // or trailing words ("...at 6 pm") get truncated.
                if isFinal {
                    self.deliver()
                }
            }
        }
    }

    /// Stop capture, wait for the recognizer's final transcription
    /// (with a safety timeout), then hand back the words.
    func end(completion: @escaping (String) -> Void) {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()

        finishCompletion = completion
        let timeout = DispatchWorkItem { [weak self] in
            self?.deliver()
        }
        finishTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: timeout)
    }

    private func deliver() {
        finishTimeout?.cancel()
        finishTimeout = nil
        guard let completion = finishCompletion else { return }
        finishCompletion = nil
        let text = transcript
        if text.isEmpty, failure == nil {
            failure = availabilityHint
        }
        task?.cancel()
        task = nil
        request = nil
        level = 0
        completion(text)
    }
}
