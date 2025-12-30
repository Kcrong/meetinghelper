import Foundation
import AWSTranscribeStreaming

class TranscribeService: ObservableObject {
    private var client: TranscribeStreamingClient?
    private var credentials: AWSCredentials?
    private var continuation: AsyncStream<TranscriptionResult>.Continuation?
    private var isRunning = false
    
    @MainActor @Published var isConnected = false
    
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
        
        print("🔗 [Transcribe] Connecting (region: \(credentials.region), language: \(language))...")
        
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
            // 영어 고정 + 화자 분리 + 정확도 개선 옵션
            print("✅ [Transcribe] Language: en-US, Speaker diarization + Stabilization enabled")
            let input = StartStreamTranscriptionInput(
                audioStream: createAudioStream(from: audioStream),
                enablePartialResultsStabilization: true,
                languageCode: .enUs,
                mediaEncoding: .pcm,
                mediaSampleRateHertz: 16000,
                partialResultsStability: .high,
                showSpeakerLabel: true
            )
            
            print("✅ [Transcribe] Starting stream transcription")
            
            let output = try await client.startStreamTranscription(input: input)
            
            guard let transcriptStream = output.transcriptResultStream else {
                print("❌ [Transcribe] No transcript stream received")
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
