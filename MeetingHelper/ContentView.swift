import SwiftUI

struct ContentView: View {
    @StateObject private var store = TranscriptionStore()
    @StateObject private var audioManager = AudioCaptureManager()
    @StateObject private var transcribeService = TranscribeService()
    @StateObject private var chatService = ChatService()
    @StateObject private var settings = SettingsManager()
    
    @State private var showSettings = false
    @State private var chatInput = ""
    @State private var chatHistory: [ChatMessage] = []
    
    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                settingsPanel
            } else {
                mainPanel
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
    }
    
    private var mainPanel: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Meeting Helper")
                    .font(.title2.bold())
                Spacer()
                if store.state == .recording {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Recording").foregroundColor(.secondary).font(.caption)
                }
                Button("Settings") { showSettings = true }
            }
            
            // Split view: Transcription (left) + Chat (right)
            HSplitView {
                // Transcription Panel
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Transcription").font(.headline)
                        Spacer()
                        // Audio Input
                        Picker("", selection: $settings.audioInputModeRaw) {
                            ForEach(AudioInputMode.allCases, id: \.rawValue) { mode in
                                Text(mode.rawValue).tag(mode.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                        .disabled(store.state == .recording)
                        
                        if settings.audioInputMode != .systemOnly {
                            Picker("", selection: Binding(
                                get: { audioManager.selectedMicrophoneID ?? "" },
                                set: { audioManager.selectedMicrophoneID = $0 }
                            )) {
                                ForEach(audioManager.availableMicrophones, id: \.uniqueID) { mic in
                                    Text(mic.localizedName).tag(mic.uniqueID)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                            .disabled(store.state == .recording)
                        }
                    }
                    .onAppear { audioManager.refreshMicrophones() }
                    
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(store.displayText.isEmpty ? "트랜스크립션이 여기에 표시됩니다..." : store.displayText)
                                .foregroundColor(store.displayText.isEmpty ? .gray : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .id("bottom")
                        }
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .onChange(of: store.displayText) { _ in
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .frame(minWidth: 250)
                
                // Chat Panel
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI Assistant")
                        .font(.headline)
                    
                    // Chat history
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(chatHistory) { message in
                                    ChatBubble(message: message)
                                }
                            }
                            .padding(8)
                            .id("chatBottom")
                        }
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(8)
                        .onChange(of: chatHistory.count) { _ in
                            proxy.scrollTo("chatBottom", anchor: .bottom)
                        }
                    }
                    
                    // Quick actions
                    HStack(spacing: 4) {
                        ForEach(settings.quickPrompts) { qp in
                            QuickButton(qp.label) { askQuick(qp.prompt) }
                        }
                    }
                    
                    // Input
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
                }
                .frame(minWidth: 250)
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
                
                Button("Clear All") {
                    store.clear()
                    chatHistory.removeAll()
                }
                .disabled(store.state == .recording)
                
                Spacer()
            }
            
            // Transcribe Settings (slider style)
            HStack(spacing: 20) {
                SliderSetting(label: "버퍼", value: $settings.audioBufferSize, options: [1024, 2048, 4096, 8192], labels: ["1024", "2048", "4096", "8192"], tooltip: "낮음: 빠른 반응, 끊김 가능\n높음: 안정적, 지연 증가")
                SliderSetting(label: "Stability", value: $settings.partialResultsStabilityIndex, options: [0, 1, 2, 3], labels: ["Off", "Low", "Med", "High"], tooltip: "낮음: 빠른 표시, 텍스트 자주 변경\n높음: 안정적 텍스트, 화자분리 정확도 저하 가능")
                SliderSetting(label: "Sample", value: $settings.transcribeSampleRate, options: [8000, 16000, 32000], labels: ["8K", "16K", "32K"], tooltip: "낮음: 낮은 대역폭, 음질 저하\n높음: 고음질, 처리량 증가")
            }
            .disabled(store.state == .recording)
            
            if case .error(let message) = store.state {
                Text(message).foregroundColor(.red).font(.caption)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Settings").font(.title2.bold())
                    Spacer()
                    Button("Done") { showSettings = false }.buttonStyle(.borderedProminent)
                }
                
                GroupBox("AWS Credentials") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Access Key").font(.caption)
                        TextField("AKIA...", text: $settings.accessKey).textFieldStyle(.roundedBorder)
                        
                        Text("Secret Key").font(.caption)
                        SecureField("Secret Key", text: $settings.secretKey).textFieldStyle(.roundedBorder)
                        
                        Text("Region (Transcribe)").font(.caption)
                        Picker("", selection: $settings.region) {
                            Text("us-east-1").tag("us-east-1")
                            Text("us-west-2").tag("us-west-2")
                            Text("ap-northeast-2 (Seoul)").tag("ap-northeast-2")
                        }.labelsHidden()
                        
                        Text("Note: AI Chat uses us-east-1 (Bedrock)").font(.caption2).foregroundColor(.secondary)
                    }.padding(.vertical, 4)
                }
                
                GroupBox("AI Chat") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Chat History Limit").font(.caption)
                        Picker("", selection: $settings.chatHistoryLimit) {
                            Text("10 messages").tag(10)
                            Text("20 messages").tag(20)
                            Text("50 messages").tag(50)
                            Text("Unlimited").tag(999)
                        }.labelsHidden()
                        Text("More history = better context, but slower & costlier").font(.caption2).foregroundColor(.secondary)
                    }.padding(.vertical, 4)
                }
                
                GroupBox("System Prompt") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI에게 전달되는 기본 지시사항").font(.caption)
                        TextEditor(text: $settings.systemPrompt)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 100)
                            .border(Color.gray.opacity(0.3))
                    }.padding(.vertical, 4)
                }
                
                GroupBox("Quick Action Buttons") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(settings.quickPrompts.indices, id: \.self) { index in
                            HStack {
                                TextField("이름", text: $settings.quickPrompts[index].label)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                    .onChange(of: settings.quickPrompts[index].label) { _ in settings.saveQuickPrompts() }
                                TextField("프롬프트", text: $settings.quickPrompts[index].prompt)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: settings.quickPrompts[index].prompt) { _ in settings.saveQuickPrompts() }
                                Button(action: { settings.deleteQuickPrompt(at: index) }) {
                                    Image(systemName: "minus.circle.fill").foregroundColor(.red)
                                }.buttonStyle(.plain)
                            }
                        }
                        Button(action: { settings.addQuickPrompt() }) {
                            Label("버튼 추가", systemImage: "plus.circle.fill")
                        }.buttonStyle(.plain)
                    }.padding(.vertical, 4)
                }
                
                Spacer()
            }
        }
    }
    
    private func sendQuestion() {
        guard !chatInput.isEmpty else { return }
        let question = chatInput
        chatInput = ""
        
        // Add user message
        chatHistory.append(ChatMessage(role: .user, content: question))
        
        // Add placeholder for assistant
        let assistantMessage = ChatMessage(role: .assistant, content: "")
        chatHistory.append(assistantMessage)
        let assistantIndex = chatHistory.count - 1
        
        // Convert chat history for API
        let historyForAPI = chatHistory.dropLast().map { msg in
            ChatHistoryItem(
                role: msg.role == .user ? "user" : "assistant",
                content: msg.content
            )
        }
        
        Task {
            if !chatService.isConfigured {
                try? await chatService.configure(credentials: settings.credentials)
            }
            
            for await chunk in chatService.ask(
                question: question,
                transcription: store.displayText,
                chatHistory: Array(historyForAPI),
                historyLimit: settings.chatHistoryLimit,
                systemPromptTemplate: settings.systemPrompt
            ) {
                await MainActor.run {
                    chatHistory[assistantIndex].content += chunk
                }
            }
        }
    }
    
    private func askQuick(_ question: String) {
        chatInput = question
        sendQuestion()
    }
    
    private func toggleRecording() {
        if store.state == .recording { stopRecording() }
        else { startRecording() }
    }
    
    private func startRecording() {
        guard settings.isConfigured else {
            store.state = .error("AWS 자격 증명을 설정하세요")
            showSettings = true
            return
        }
        
        store.state = .preparing
        transcribeService.configure(credentials: settings.credentials)
        transcribeService.settings.sampleRate = settings.transcribeSampleRate
        transcribeService.settings.stability = settings.partialResultsStability
        audioManager.bufferSize = settings.audioBufferSize
        
        Task {
            do {
                let audioStream = try await audioManager.startCapture(mode: settings.audioInputMode)
                let resultStream = try await transcribeService.startTranscription(
                    audioStream: audioStream, language: settings.language
                )
                store.state = .recording
                
                for await result in resultStream {
                    await MainActor.run { store.appendResult(result) }
                }
            } catch {
                await MainActor.run { store.state = .error(error.localizedDescription) }
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

// MARK: - Chat Models

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    var content: String
    let timestamp = Date()
}

enum ChatRole {
    case user, assistant
}

struct ChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.role == .user ? "You" : "AI")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(message.content.isEmpty ? "..." : message.content)
                    .padding(8)
                    .background(message.role == .user ? Color.blue.opacity(0.2) : Color.gray.opacity(0.15))
                    .cornerRadius(8)
            }
            
            if message.role == .assistant { Spacer() }
        }
    }
}

// MARK: - Slider Setting Component

struct SliderSetting<T: Hashable>: View {
    let label: String
    @Binding var value: T
    let options: [T]
    let labels: [String]
    var tooltip: String = ""
    @State private var showTooltip = false
    
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text(label).font(.caption2).foregroundColor(.secondary)
                if !tooltip.isEmpty {
                    Text("?")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .frame(width: 12, height: 12)
                        .background(Color.gray)
                        .clipShape(Circle())
                        .onHover { showTooltip = $0 }
                        .popover(isPresented: $showTooltip, arrowEdge: .top) {
                            Text(tooltip).font(.caption).padding(8)
                        }
                }
            }
            HStack(spacing: 0) {
                ForEach(Array(zip(options.indices, options)), id: \.0) { index, option in
                    Button(labels[index]) {
                        value = option
                    }
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(value == option ? Color.accentColor : Color.gray.opacity(0.2))
                    .foregroundColor(value == option ? .white : .primary)
                }
            }
            .cornerRadius(4)
        }
    }
}
