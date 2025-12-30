import SwiftUI

struct QuickPrompt: Codable, Identifiable {
    var id = UUID()
    var label: String
    var prompt: String
}

enum PartialResultsStability: String, CaseIterable {
    case off = "끔"
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
        QuickPrompt(label: "요약", prompt: "지금까지 회의 내용을 간단히 요약해줘"),
        QuickPrompt(label: "액션 아이템", prompt: "회의에서 나온 액션 아이템들을 정리해줘"),
        QuickPrompt(label: "결정 사항", prompt: "회의에서 결정된 사항들을 알려줘")
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
        quickPrompts.append(QuickPrompt(label: "새 버튼", prompt: ""))
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
}
