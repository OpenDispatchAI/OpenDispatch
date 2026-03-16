import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
final class SpeechCaptureManager: ObservableObject {
    @Published var transcript = ""
    @Published var isListening = false
    @Published var errorMessage: String?

    private var session: SpeechCaptureSession?
    private var isStarting = false

    func start() async {
        guard isListening == false, isStarting == false else { return }
        isStarting = true
        defer { isStarting = false }

        #if targetEnvironment(simulator)
        errorMessage = "Live speech capture isn't supported in Simulator. Run OpenDispatch on a physical iPhone or iPad."
        return
        #endif

        let authorization = await Task.detached(priority: .userInitiated) {
            await SpeechAuthorizationRequester.requestAuthorizationState()
        }.value
        guard authorization.speechAuthorized else {
            errorMessage = "Speech recognition permission is required."
            return
        }
        guard authorization.microphoneAuthorized else {
            errorMessage = "Microphone permission is required."
            return
        }

        transcript = ""
        errorMessage = nil

        do {
            let newSession = try SpeechCaptureSession(
                locale: .current,
                onTranscript: { [weak self] text in
                    Task { @MainActor in
                        self?.transcript = text
                    }
                },
                onStateChange: { [weak self] state in
                    Task { @MainActor in
                        self?.apply(state: state)
                    }
                }
            )

            try newSession.start()
            session = newSession
            isListening = true
        } catch {
            session = nil
            isListening = false
            errorMessage = Self.message(for: error)
        }
    }

    func stop() {
        session?.stop()
        session = nil
        isListening = false
    }

    private func apply(state: SpeechCaptureSession.State) {
        switch state {
        case .listening:
            isListening = true
        case let .finished(errorMessage):
            session = nil
            isListening = false
            if let errorMessage {
                self.errorMessage = errorMessage
            }
        }
    }
    private static func message(for error: Error) -> String {
        if let error = error as? SpeechCaptureError {
            return error.errorDescription ?? "Unable to start listening."
        }
        return error.localizedDescription
    }
}

private struct SpeechAuthorizationState: Sendable {
    let speechAuthorized: Bool
    let microphoneAuthorized: Bool
}

private enum SpeechAuthorizationRequester {
    nonisolated static func requestAuthorizationState() async -> SpeechAuthorizationState {
        async let speechAuthorized = requestSpeechAuthorization()
        async let microphoneAuthorized = requestMicrophoneAuthorization()
        return await SpeechAuthorizationState(
            speechAuthorized: speechAuthorized,
            microphoneAuthorized: microphoneAuthorized
        )
    }

    private nonisolated static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation(isolation: nil) { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private nonisolated static func requestMicrophoneAuthorization() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}

private nonisolated final class SpeechCaptureSession: @unchecked Sendable {
    enum State: Sendable {
        case listening
        case finished(errorMessage: String?)
    }

    private let audioEngine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer
    private let audioSession = AVAudioSession.sharedInstance()
    private let onTranscript: @Sendable (String) -> Void
    private let onStateChange: @Sendable (State) -> Void

    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var hasInstalledTap = false
    private var hasFinished = false

    init(
        locale: Locale,
        onTranscript: @escaping @Sendable (String) -> Void,
        onStateChange: @escaping @Sendable (State) -> Void
    ) throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw SpeechCaptureError.recognizerUnavailable
        }

        self.recognizer = recognizer
        self.onTranscript = onTranscript
        self.onStateChange = onStateChange
        self.recognizer.defaultTaskHint = .dictation
    }

    func start() throws {
        guard recognizer.isAvailable else {
            throw SpeechCaptureError.recognizerUnavailable
        }

        teardown(emitState: false)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request
        hasFinished = false

        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let hardwareInputFormat = inputNode.inputFormat(forBus: 0)
        guard hardwareInputFormat.sampleRate > 0, hardwareInputFormat.channelCount > 0 else {
            throw SpeechCaptureError.invalidInputFormat
        }
        let tapFormat = inputNode.outputFormat(forBus: 0)
        guard tapFormat.sampleRate > 0, tapFormat.channelCount > 0 else {
            throw SpeechCaptureError.invalidInputFormat
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        hasInstalledTap = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                self.onTranscript(result.bestTranscription.formattedString)
                if result.isFinal {
                    self.teardown(emitState: true, errorMessage: nil)
                }
            }

            if let error {
                self.teardown(emitState: true, errorMessage: error.localizedDescription)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        onStateChange(.listening)
    }

    func stop() {
        teardown(emitState: true, errorMessage: nil)
    }

    private func teardown(emitState: Bool, errorMessage: String? = nil) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)

        guard emitState, hasFinished == false else { return }
        hasFinished = true
        onStateChange(.finished(errorMessage: errorMessage))
    }
}

private enum SpeechCaptureError: LocalizedError {
    case invalidInputFormat
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidInputFormat:
            "No microphone input is available on this device."
        case .recognizerUnavailable:
            "Speech recognition is currently unavailable."
        }
    }
}
