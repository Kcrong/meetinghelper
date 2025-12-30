import Foundation
import AWSTranscribeStreaming

struct TranscribeSettings {
    var sampleRate: Int = 16000
    var stability: PartialResultsStability = .off
}

class TranscribeService: ObservableObject {
    private var client: TranscribeStreamingClient?
    private var credentials: AWSCredentials?
    private var continuation: AsyncStream<TranscriptionResult>.Continuation?
    private var isRunning = false
    var settings = TranscribeSettings()
    
    @MainActor @Published var isConnected = false
    @MainActor @Published var lastError: String?
    
    func configure(credentials: AWSCredentials) {
        self.credentials = credentials
    }
    
    func startTranscription(audioStream: AsyncStream<Data>, language: String) async throws -> AsyncStream<TranscriptionResult> {
        guard let credentials, credentials.isValid else {
            throw TranscribeError.invalidCredentials
        }
        
        setenv("AWS_ACCESS_KEY_ID", credentials.accessKey, 1)
        setenv("AWS_SECRET_ACCESS_KEY", credentials.secretKey, 1)
        setenv("AWS_REGION", credentials.region, 1)
        
        let config = try await TranscribeStreamingClient.TranscribeStreamingClientConfiguration(
            region: credentials.region
        )
        
        client = TranscribeStreamingClient(config: config)
        isRunning = true
        
        print("[MH-TRANSCRIBE] Connecting (region: \(credentials.region), sampleRate: \(settings.sampleRate), stability: \(settings.stability.rawValue))")
        
        let resultStream = AsyncStream<TranscriptionResult> { continuation in
            self.continuation = continuation
        }
        
        Task {
            await streamTranscription(audioStream: audioStream, language: language)
        }
        
        await MainActor.run { isConnected = true }
        return resultStream
    }
    
    private func streamTranscription(audioStream: AsyncStream<Data>, language: String) async {
        guard let client else { return }
        
        do {
            let input: StartStreamTranscriptionInput
            
            if settings.stability != .off {
                let awsStability: TranscribeStreamingClientTypes.PartialResultsStability = {
                    switch settings.stability {
                    case .low: return .low
                    case .medium: return .medium
                    case .high: return .high
                    case .off: return .low
                    }
                }()
                
                input = StartStreamTranscriptionInput(
                    audioStream: createAudioStream(from: audioStream),
                    enablePartialResultsStabilization: true,
                    languageCode: .enUs,
                    mediaEncoding: .pcm,
                    mediaSampleRateHertz: settings.sampleRate,
                    partialResultsStability: awsStability,
                    showSpeakerLabel: true
                )
            } else {
                input = StartStreamTranscriptionInput(
                    audioStream: createAudioStream(from: audioStream),
                    languageCode: .enUs,
                    mediaEncoding: .pcm,
                    mediaSampleRateHertz: settings.sampleRate,
                    showSpeakerLabel: true
                )
            }
            
            print("[MH-TRANSCRIBE] Starting stream transcription")
            
            let output = try await client.startStreamTranscription(input: input)
            
            guard let transcriptStream = output.transcriptResultStream else {
                print("[MH-TRANSCRIBE] No transcript stream received")
                return
            }
            
            for try await event in transcriptStream {
                if case .transcriptevent(let transcriptEvent) = event {
                    processTranscriptEvent(transcriptEvent)
                }
            }
            print("✅ [Transcribe] Stream completed")
        } catch {
            print("❌ [Transcribe] Error: \(error)")
            let errorMessage = parseTranscribeError(error)
            await MainActor.run { self.lastError = errorMessage }
        }
        
        continuation?.finish()
        await MainActor.run { isConnected = false }
    }
    
    private func processTranscriptEvent(_ event: TranscribeStreamingClientTypes.TranscriptEvent) {
        guard let results = event.transcript?.results else { return }
        
        for result in results {
            guard let alternatives = result.alternatives, let first = alternatives.first else { continue }
            let text = first.transcript ?? ""
            let isPartial = result.isPartial ?? true
            
            if text.isEmpty { continue }
            
            // 화자 라벨 추출
            var speakerLabel: String? = nil
            if let items = first.items {
                let speakers = items.compactMap { $0.speaker }
                if let mostCommon = speakers.mostCommon() {
                    speakerLabel = "Speaker \(mostCommon)"
                }
            }
            
            let prefix = speakerLabel ?? ""
            print("📝 [Transcribe] \(isPartial ? "Partial" : "Final") \(prefix): \(text)")
            
            continuation?.yield(TranscriptionResult(
                text: text,
                isPartial: isPartial,
                timestamp: Date(),
                speakerLabel: speakerLabel
            ))
        }
    }
    
    private func createAudioStream(from audioStream: AsyncStream<Data>) -> AsyncThrowingStream<TranscribeStreamingClientTypes.AudioStream, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                var chunkCount = 0
                for await data in audioStream {
                    if !self.isRunning { break }
                    chunkCount += 1
                    if chunkCount % 50 == 0 {
                        print("📤 [Transcribe] Sent \(chunkCount) audio chunks")
                    }
                    let audioEvent = TranscribeStreamingClientTypes.AudioEvent(audioChunk: data)
                    continuation.yield(.audioevent(audioEvent))
                }
                continuation.finish()
            }
        }
    }
    
    func stopTranscription() {
        print("🛑 [Transcribe] Stopping transcription")
        isRunning = false
        continuation?.finish()
        continuation = nil
        client = nil
        Task { @MainActor in isConnected = false }
    }
    
    private func languageCode(from language: String) -> TranscribeStreamingClientTypes.LanguageCode {
        .enUs  // 영어 고정
    }
    
    private func parseTranscribeError(_ error: Error) -> String {
        let errorString = String(describing: error)
        
        if errorString.contains("InvalidSignatureException") || errorString.contains("SignatureDoesNotMatch") {
            return "AWS 자격 증명이 잘못되었습니다. Access Key와 Secret Key를 확인하세요."
        } else if errorString.contains("UnrecognizedClientException") || errorString.contains("InvalidClientTokenId") {
            return "AWS Access Key가 유효하지 않습니다."
        } else if errorString.contains("AccessDeniedException") || errorString.contains("AccessDenied") {
            return "AWS Transcribe 접근 권한이 없습니다. IAM 정책을 확인하세요."
        } else if errorString.contains("ExpiredTokenException") {
            return "AWS 자격 증명이 만료되었습니다."
        } else if errorString.contains("ServiceUnavailable") {
            return "AWS Transcribe 서비스를 사용할 수 없습니다. 잠시 후 다시 시도하세요."
        } else if errorString.contains("LimitExceededException") {
            return "동시 스트림 한도를 초과했습니다. 잠시 후 다시 시도하세요."
        } else if errorString.contains("BadRequestException") {
            return "잘못된 요청입니다. 오디오 설정을 확인하세요."
        } else {
            return "Transcribe 오류: \(error.localizedDescription)"
        }
    }
}

private extension Array where Element: Hashable {
    func mostCommon() -> Element? {
        let counts = reduce(into: [:]) { $0[$1, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}

enum TranscribeError: Error, LocalizedError {
    case invalidCredentials
    case connectionFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "AWS 자격 증명이 유효하지 않습니다"
        case .connectionFailed: return "연결에 실패했습니다"
        }
    }
}
