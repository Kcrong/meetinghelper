import SwiftUI

struct ContentView: View {
    @StateObject private var store = TranscriptionStore()
    @StateObject private var audioManager = AudioCaptureManager()
    @StateObject private var transcribeService = TranscribeService()
    @StateObject private var chatService = ChatService()
    @StateObject private var settings = SettingsManager()
    
    @State private var showSettings = false
    @State private var chatInput = ""
    @State private var chatResponse = ""
    @State private var showChat = false
    
    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                settingsPanel
            } else {
                mainPanel
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
    }
    
    private var mainPanel: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Meeting Helper")
                    .font(.title2.bold())
                Spacer()
                Button(showChat ? "Transcription" : "Ask AI") {
                    showChat.toggle()
                }
                Button("Settings") { showSettings = true }
            }
            
            if showChat {
                chatPanel
            } else {
                transcriptionPanel
            }
            
            // Controls
            HStack(spacing: 16) {
                Button(action: toggleRecording) {
                    Label(
                        store.state == .recording ? "Stop" : "Start",
                        systemImage: store.state == .recording ? "stop.fill" : "mic.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(store.state == .recording ? .red : .blue)
                .disabled(store.state == .preparing || store.state == .stopping)
                
                Button("Clear") { store.clear(); chatResponse = "" }
                    .disabled(store.state == .recording)
                
                Spacer()
                
                if store.state == .recording {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("Recording...")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            
            if case .error(let message) = store.state {
                Text(message)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }
    
    private var transcriptionPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(store.displayText.isEmpty ? "트랜스크립션이 여기에 표시됩니다..." : store.displayText)
                    .foregroundColor(store.displayText.isEmpty ? .gray : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .id("bottom")
            }
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .onChange(of: store.displayText) { _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
    
    private var chatPanel: some View {
        VStack(spacing: 8) {
            // Response area
            ScrollView {
                Text(chatResponse.isEmpty ? "AI 응답이 여기에 표시됩니다..." : chatResponse)
                    .foregroundColor(chatResponse.isEmpty ? .gray : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color.blue.opacity(0.05))
            .cornerRadius(8)
            
            // Input area
            HStack {
                TextField("질문을 입력하세요...", text: $chatInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendQuestion() }
                
                Button(action: sendQuestion) {
                    Image(systemName: chatService.isLoading ? "hourglass" : "paperplane.fill")
                }
                .disabled(chatInput.isEmpty || chatService.isLoading)
                .buttonStyle(.borderedProminent)
            }
            
            // Quick actions
            HStack(spacing: 8) {
                QuickButton("요약해줘") { askQuick("지금까지 회의 내용을 간단히 요약해줘") }
                QuickButton("액션 아이템") { askQuick("회의에서 나온 액션 아이템들을 정리해줘") }
                QuickButton("결정 사항") { askQuick("회의에서 결정된 사항들을 알려줘") }
            }
        }
    }
    
    private func QuickButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption)
            .buttonStyle(.bordered)
            .disabled(chatService.isLoading || store.displayText.isEmpty)
    }
    
    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { showSettings = false }
                    .buttonStyle(.borderedProminent)
            }
            
            GroupBox("AWS Credentials") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Access Key")
                        .font(.caption)
                    TextField("AKIA...", text: $settings.accessKey)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("Secret Key")
                        .font(.caption)
                    SecureField("Secret Key", text: $settings.secretKey)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("Region (Transcribe)")
                        .font(.caption)
                    Picker("", selection: $settings.region) {
                        Text("us-east-1").tag("us-east-1")
                        Text("us-west-2").tag("us-west-2")
                        Text("ap-northeast-2 (Seoul)").tag("ap-northeast-2")
                    }
                    .labelsHidden()
                    
                    Text("Note: AI Chat uses us-east-1 (Bedrock)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            Spacer()
        }
    }
    
    private func sendQuestion() {
        guard !chatInput.isEmpty else { return }
        let question = chatInput
        chatInput = ""
        chatResponse = ""
        
        Task {
            if !chatService.isConfigured {
                try? await chatService.configure(credentials: settings.credentials)
            }
            
            for await chunk in chatService.ask(question: question, transcription: store.displayText) {
                await MainActor.run {
                    chatResponse += chunk
                }
            }
        }
    }
    
    private func askQuick(_ question: String) {
        chatInput = question
        sendQuestion()
    }
    
    private func toggleRecording() {
        if store.state == .recording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        guard settings.isConfigured else {
            store.state = .error("AWS 자격 증명을 설정하세요")
            showSettings = true
            return
        }
        
        store.state = .preparing
        transcribeService.configure(credentials: settings.credentials)
        print("🚀 [App] Starting recording with region: \(settings.region)")
        
        Task {
            do {
                let audioStream = try await audioManager.startCapture()
                print("🎤 [App] Audio capture started, connecting to AWS...")
                let resultStream = try await transcribeService.startTranscription(
                    audioStream: audioStream,
                    language: settings.language
                )
                print("✅ [App] Transcription started")
                store.state = .recording
                
                for await result in resultStream {
                    await MainActor.run {
                        store.appendResult(result)
                    }
                }
            } catch {
                print("❌ [App] Error: \(error)")
                await MainActor.run {
                    store.state = .error(error.localizedDescription)
                }
            }
        }
    }
    
    private func stopRecording() {
        store.state = .stopping
        audioManager.stopCapture()
        transcribeService.stopTranscription()
        store.state = .idle
    }
}
