import Foundation
import AWSBedrockRuntime

class ChatService: ObservableObject {
    private var bedrockClient: BedrockRuntimeClient?
    private let modelId = "anthropic.claude-3-haiku-20240307-v1:0"
    private let region = "us-east-1"
    
    @MainActor @Published var isLoading = false
    @MainActor @Published var lastResponse = ""
    
    var isConfigured: Bool { bedrockClient != nil }
    
    func configure(credentials: AWSCredentials) async throws {
        setenv("AWS_ACCESS_KEY_ID", credentials.accessKey, 1)
        setenv("AWS_SECRET_ACCESS_KEY", credentials.secretKey, 1)
        setenv("AWS_REGION", region, 1)
        
        let config = try await BedrockRuntimeClient.BedrockRuntimeClientConfiguration(region: region)
        bedrockClient = BedrockRuntimeClient(config: config)
        print("✅ [Chat] Bedrock client configured (region: \(region))")
    }
    
    /// 스트리밍 응답으로 질문에 답변
    func ask(question: String, transcription: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                await MainActor.run { self.isLoading = true }
                defer { Task { @MainActor in self.isLoading = false } }
                
                guard let client = bedrockClient else {
                    continuation.yield("Error: Bedrock client not configured")
                    continuation.finish()
                    return
                }
                
                let systemPrompt = """
                You are a helpful meeting assistant. Answer questions based on the meeting transcription provided.
                Be concise and direct. If the information is not in the transcription, say so.
                Respond in the same language as the user's question.
                """
                
                let userMessage = """
                Meeting Transcription:
                ---
                \(transcription.suffix(8000))
                ---
                
                Question: \(question)
                """
                
                let body: [String: Any] = [
                    "anthropic_version": "bedrock-2023-05-31",
                    "max_tokens": 500,
                    "system": systemPrompt,
                    "messages": [
                        ["role": "user", "content": userMessage]
                    ]
                ]
                
                guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
                    continuation.yield("Error: Failed to create request")
                    continuation.finish()
                    return
                }
                
                do {
                    let input = InvokeModelWithResponseStreamInput(
                        body: bodyData,
                        contentType: "application/json",
                        modelId: modelId
                    )
                    
                    let output = try await client.invokeModelWithResponseStream(input: input)
                    
                    guard let stream = output.body else {
                        continuation.yield("Error: No response stream")
                        continuation.finish()
                        return
                    }
                    
                    var fullResponse = ""
                    
                    for try await event in stream {
                        if case .chunk(let payload) = event,
                           let data = payload.bytes,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let delta = json["delta"] as? [String: Any],
                           let text = delta["text"] as? String {
                            fullResponse += text
                            continuation.yield(text)
                        }
                    }
                    
                    await MainActor.run { self.lastResponse = fullResponse }
                    print("✅ [Chat] Response complete: \(fullResponse.prefix(50))...")
                    
                } catch {
                    print("❌ [Chat] Error: \(error)")
                    continuation.yield("Error: \(error.localizedDescription)")
                }
                
                continuation.finish()
            }
        }
    }
    
    /// 비스트리밍 (간단한 요청용)
    func askSync(question: String, transcription: String) async -> String {
        var result = ""
        for await chunk in ask(question: question, transcription: transcription) {
            result += chunk
        }
        return result
    }
}
