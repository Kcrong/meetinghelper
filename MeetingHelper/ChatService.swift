import Foundation
import AWSBedrockRuntime

class ChatService: ObservableObject {
    private var bedrockClient: BedrockRuntimeClient?
    private let modelId = "anthropic.claude-3-haiku-20240307-v1:0"
    private let region = "us-east-1"
    private var currentTask: Task<Void, Never>?
    
    @MainActor @Published var isLoading = false
    @MainActor @Published var lastResponse = ""
    
    var isConfigured: Bool { bedrockClient != nil }
    
    func stopGenerating() {
        currentTask?.cancel()
        currentTask = nil
        Task { @MainActor in isLoading = false }
    }
    
    func configure(credentials: AWSCredentials) async throws {
        setenv("AWS_ACCESS_KEY_ID", credentials.accessKey, 1)
        setenv("AWS_SECRET_ACCESS_KEY", credentials.secretKey, 1)
        setenv("AWS_REGION", region, 1)
        
        let config = try await BedrockRuntimeClient.BedrockRuntimeClientConfiguration(region: region)
        bedrockClient = BedrockRuntimeClient(config: config)
        print("✅ [Chat] Bedrock client configured (region: \(region))")
    }
    
    /// Stream response to question
    func ask(question: String, transcription: String, chatHistory: [ChatHistoryItem] = [], historyLimit: Int = 20, systemPromptTemplate: String? = nil) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                await MainActor.run { self.isLoading = true }
                defer { Task { @MainActor in self.isLoading = false } }
                
                guard let client = bedrockClient else {
                    continuation.yield("Error: Bedrock client not configured")
                    continuation.finish()
                    return
                }
                
                let template = systemPromptTemplate ?? """
                You are a helpful meeting assistant. Answer questions based on the meeting transcription provided.
                Be concise and direct. If the information is not in the transcription, say so.
                Respond in the same language as the user's question.
                """
                
                let systemPrompt = """
                \(template)
                
                Meeting Transcription:
                ---
                \(transcription.suffix(6000))
                ---
                """
                
                // Build messages array with chat history (filter and validate)
                var messages: [[String: String]] = []
                var lastRole = ""
                
                for item in chatHistory.suffix(historyLimit) {
                    // Skip empty messages and consecutive same roles
                    if item.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                    if item.role == lastRole { continue }
                    messages.append(["role": item.role, "content": item.content])
                    lastRole = item.role
                }
                
                // Ensure conversation starts with user (Claude requirement)
                while let first = messages.first, first["role"] == "assistant" {
                    messages.removeFirst()
                }
                
                // Add current question
                if lastRole == "user" && !messages.isEmpty {
                    // If last message was user, remove to avoid consecutive user messages
                    messages.removeLast()
                }
                messages.append(["role": "user", "content": question])
                
                print("🔍 [Chat] Sending \(messages.count) messages")
                for (i, msg) in messages.enumerated() {
                    print("  [\(i)] \(msg["role"] ?? "?"): \(msg["content"]?.prefix(50) ?? "")...")
                }
                
                let body: [String: Any] = [
                    "anthropic_version": "bedrock-2023-05-31",
                    "max_tokens": 500,
                    "system": systemPrompt,
                    "messages": messages
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
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
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
                    if Task.isCancelled { 
                        continuation.finish()
                        return 
                    }
                    print("❌ [Chat] Error: \(error)")
                    print("❌ [Chat] Error details: \(String(describing: error))")
                    continuation.yield("Error: \(error.localizedDescription)")
                }
                
                continuation.finish()
            }
            self.currentTask = task
        }
    }
    
    /// Non-streaming (for simple requests)
    func askSync(question: String, transcription: String, chatHistory: [ChatHistoryItem] = [], systemPromptTemplate: String? = nil) async -> String {
        var result = ""
        for await chunk in ask(question: question, transcription: transcription, chatHistory: chatHistory, systemPromptTemplate: systemPromptTemplate) {
            result += chunk
        }
        return result
    }
}

struct ChatHistoryItem {
    let role: String  // "user" or "assistant"
    let content: String
}
