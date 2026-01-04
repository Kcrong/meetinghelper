import SwiftUI
import AWSTranscribeStreaming
import AWSBedrockRuntime

struct QuickPrompt: Codable, Identifiable {
    var id = UUID()
    var label: String
    var prompt: String
}

enum PartialResultsStability: String, CaseIterable {
    case off = "Off"
    case low = "Low"
    case medium = "Medium"
    case high = "High"
}

class SettingsManager: ObservableObject {
    @AppStorage("accessKey") var accessKey = ""
    @AppStorage("secretKey") var secretKey = ""
    @AppStorage("region") var region = "us-east-1"
    @AppStorage("language") var language = "ko-KR"
    @AppStorage("chatHistoryLimit") var chatHistoryLimit = 20
    @AppStorage("audioInputMode") var audioInputModeRaw = AudioInputMode.both.rawValue
    
    // MARK: - Transcribe Settings
    @AppStorage("audioBufferSize") var audioBufferSize = 8192
    @AppStorage("partialResultsStability") var partialResultsStabilityRaw = PartialResultsStability.low.rawValue
    @AppStorage("transcribeSampleRate") var transcribeSampleRate = 16000
    
    var audioInputMode: AudioInputMode {
        get { AudioInputMode(rawValue: audioInputModeRaw) ?? .both }
        set { audioInputModeRaw = newValue.rawValue }
    }
    
    var partialResultsStability: PartialResultsStability {
        get { PartialResultsStability(rawValue: partialResultsStabilityRaw) ?? .off }
        set { partialResultsStabilityRaw = newValue.rawValue }
    }
    
    var partialResultsStabilityIndex: Int {
        get { PartialResultsStability.allCases.firstIndex(of: partialResultsStability) ?? 0 }
        set { partialResultsStability = PartialResultsStability.allCases[newValue] }
    }
    
    // MARK: - Prompts
    @AppStorage("systemPrompt") var systemPrompt = """
You are a helpful meeting assistant. Answer questions based on the meeting transcription provided.
Be concise and direct. If the information is not in the transcription, say so.
Respond in the same language as the user's question.
"""
    
    @Published var quickPrompts: [QuickPrompt] = []
    
    private let quickPromptsKey = "quickPrompts"
    private static let defaultQuickPrompts = [
        QuickPrompt(label: "Summary", prompt: "Summarize the meeting so far"),
        QuickPrompt(label: "Action Items", prompt: "List the action items from the meeting"),
        QuickPrompt(label: "Decisions", prompt: "What decisions were made in the meeting?")
    ]
    
    init() {
        loadQuickPrompts()
    }
    
    private func loadQuickPrompts() {
        if let data = UserDefaults.standard.data(forKey: quickPromptsKey),
           let decoded = try? JSONDecoder().decode([QuickPrompt].self, from: data) {
            quickPrompts = decoded
        } else {
            quickPrompts = Self.defaultQuickPrompts
        }
    }
    
    func saveQuickPrompts() {
        if let data = try? JSONEncoder().encode(quickPrompts) {
            UserDefaults.standard.set(data, forKey: quickPromptsKey)
        }
    }
    
    func addQuickPrompt() {
        quickPrompts.append(QuickPrompt(label: "New Button", prompt: ""))
        saveQuickPrompts()
    }
    
    func deleteQuickPrompt(at index: Int) {
        guard quickPrompts.indices.contains(index) else { return }
        quickPrompts.remove(at: index)
        saveQuickPrompts()
    }
    
    var credentials: AWSCredentials {
        AWSCredentials(accessKey: accessKey, secretKey: secretKey, region: region)
    }
    
    var isConfigured: Bool {
        credentials.isValid
    }
    
    // Validate AWS credentials
    func validateCredentials() async -> (success: Bool, message: String) {
        guard isConfigured else {
            return (false, "Please enter Access Key and Secret Key")
        }
        
        setenv("AWS_ACCESS_KEY_ID", accessKey, 1)
        setenv("AWS_SECRET_ACCESS_KEY", secretKey, 1)
        setenv("AWS_REGION", region, 1)
        
        // Validate Transcribe
        do {
            let transcribeConfig = try await TranscribeStreamingClient.TranscribeStreamingClientConfiguration(region: region)
            let transcribeClient = TranscribeStreamingClient(config: transcribeConfig)
            
            // Try starting a stream (empty audio, immediately finish)
            let emptyStream = AsyncThrowingStream<TranscribeStreamingClientTypes.AudioStream, Error> { $0.finish() }
            let input = StartStreamTranscriptionInput(
                audioStream: emptyStream,
                languageCode: .enUs,
                mediaEncoding: .pcm,
                mediaSampleRateHertz: 16000
            )
            _ = try await transcribeClient.startStreamTranscription(input: input)
        } catch {
            return (false, "Transcribe error: \(parseError(error))")
        }
        
        // Validate Bedrock
        do {
            let bedrockConfig = try await BedrockRuntimeClient.BedrockRuntimeClientConfiguration(region: "us-east-1")
            let bedrockClient = BedrockRuntimeClient(config: bedrockConfig)
            
            let payload: [String: Any] = [
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 1,
                "messages": [["role": "user", "content": "hi"]]
            ]
            let body = try JSONSerialization.data(withJSONObject: payload)
            let input = InvokeModelInput(body: body, modelId: "anthropic.claude-3-haiku-20240307-v1:0")
            _ = try await bedrockClient.invokeModel(input: input)
        } catch {
            return (false, "Bedrock error: \(parseError(error))")
        }
        
        return (true, "✓ Transcribe, Bedrock connection successful")
    }
    
    private func parseError(_ error: Error) -> String {
        let errorString = String(describing: error)
        if errorString.contains("InvalidClientTokenId") || errorString.contains("UnrecognizedClientException") {
            return "Invalid Access Key"
        } else if errorString.contains("SignatureDoesNotMatch") {
            return "Invalid Secret Key"
        } else if errorString.contains("AccessDenied") {
            return "Access denied. Check IAM policy"
        } else if errorString.contains("ExpiredToken") {
            return "Credentials expired"
        }
        return error.localizedDescription
    }
}
