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
    @State private var isRecordingPulse = false
    @State private var transcriptSearch = ""
    @State private var showTimestamps = false
    @State private var isTestingCredentials = false
    @State private var credentialsTestResult: String?
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if showSettings {
                    settingsPanel
                } else {
                    mainPanel
                }
            }
            .padding(20)
            
            // Error toast
            if case .error(let message) = store.state {
                VStack {
                    Spacer()
                    ErrorToast(message: message) {
                        store.state = .idle
                    }
                    .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(), value: store.state)
            }
            
            // Onboarding overlay
            if !settings.isConfigured && !showSettings {
                OnboardingOverlay {
                    showSettings = true
                }
            }
        }
        .frame(minWidth: 900, idealWidth: 1100, minHeight: 650, idealHeight: 750)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Main Panel
    private var mainPanel: some View {
        GeometryReader { geo in
            let isNarrow = geo.size.width < 700
            
            VStack(spacing: 20) {
                headerView
                
                if isNarrow {
                    VSplitView {
                        transcriptionPanel
                        chatPanel
                    }
                } else {
                    HSplitView {
                        transcriptionPanel
                        chatPanel
                    }
                }
                
                bottomControls
            }
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 36, height: 36)
                Image(systemName: "waveform")
                    .font(.body.bold())
                    .foregroundColor(.white)
            }
            
            Text("Meeting Helper")
                .font(.title2.bold())
            
            Spacer()
            
            if store.state == .recording {
                recordingIndicator
            }
            
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
    
    private var recordingIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .scaleEffect(isRecordingPulse ? 1.2 : 1.0)
                .opacity(isRecordingPulse ? 0.7 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isRecordingPulse)
                .onAppear { isRecordingPulse = true }
                .onDisappear { isRecordingPulse = false }
            Text("REC")
                .font(.caption.bold())
                .foregroundColor(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.red.opacity(0.15))
        .cornerRadius(16)
    }
    
    // MARK: - Transcription Panel
    private var transcriptionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Transcription", systemImage: "text.quote")
                    .font(.subheadline.weight(.semibold))
                
                // Search
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    TextField("검색", text: $transcriptSearch)
                        .textFieldStyle(.plain)
                        .font(.caption)
                }
                .padding(6)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
                .frame(width: 100)
                
                // Timestamp toggle
                Button(action: { showTimestamps.toggle() }) {
                    Image(systemName: "clock")
                        .foregroundColor(showTimestamps ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .help("타임스탬프 표시")
                
                Spacer()
                
                Picker("", selection: $settings.audioInputModeRaw) {
                    ForEach(AudioInputMode.allCases, id: \.rawValue) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
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
                    .frame(width: 140)
                    .disabled(store.state == .recording)
                }
            }
            .onAppear { audioManager.refreshMicrophones() }
            
            // Speaker management
            if !store.detectedSpeakers.isEmpty {
                SpeakerBar(store: store)
            }
            
            ScrollViewReader { proxy in
                ScrollView {
                    if store.segments.isEmpty && store.partialText.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "waveform.badge.mic")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("트랜스크립션이 여기에 표시됩니다")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 60)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(filteredSegments) { segment in
                                TranscriptRow(
                                    speaker: segment.speaker,
                                    displayName: segment.speaker.map { store.displayName(for: $0) },
                                    text: segment.text,
                                    timestamp: showTimestamps ? segment.timestamp : nil,
                                    color: speakerColor(for: segment.speaker),
                                    searchTerm: transcriptSearch
                                )
                            }
                            
                            // Partial (typing indicator)
                            if !store.partialText.isEmpty && transcriptSearch.isEmpty {
                                TranscriptRow(
                                    speaker: store.partialSpeaker,
                                    displayName: store.partialSpeaker.map { store.displayName(for: $0) },
                                    text: store.partialText,
                                    color: speakerColor(for: store.partialSpeaker),
                                    isPartial: true
                                )
                            }
                        }
                        .padding(14)
                        .textSelection(.enabled)
                        .id("bottom")
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                .onChange(of: store.segments.count) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: store.partialText) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .frame(minWidth: 300)
    }
    
    private var filteredSegments: [TranscriptionSegment] {
        guard !transcriptSearch.isEmpty else { return store.segments }
        return store.segments.filter { $0.text.localizedCaseInsensitiveContains(transcriptSearch) }
    }
    
    private let speakerColors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
    
    private func speakerColor(for speaker: String?) -> Color {
        guard let speaker = speaker,
              let index = store.detectedSpeakers.firstIndex(of: speaker) else {
            return .gray
        }
        return speakerColors[index % speakerColors.count]
    }
    
    // MARK: - Chat Panel
    private var chatPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI Assistant", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            
            ScrollViewReader { proxy in
                ScrollView {
                    if chatHistory.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("AI에게 질문해보세요")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 60)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(chatHistory) { message in
                                ChatBubble(message: message, onCopy: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(message.content, forType: .string)
                                })
                            }
                        }
                        .padding(14)
                        .id("chatBottom")
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                .onChange(of: chatHistory.count) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("chatBottom", anchor: .bottom)
                    }
                }
            }
            
            // Quick actions (scrollable)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(settings.quickPrompts) { qp in
                        QuickActionButton(
                            title: qp.label,
                            icon: quickActionIcon(for: qp.label),
                            disabled: chatService.isLoading || store.displayText.isEmpty
                        ) {
                            askQuick(qp.prompt)
                        }
                    }
                }
            }
            
            // Input + Stop button
            HStack(spacing: 10) {
                TextField("질문을 입력하세요...", text: $chatInput)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(10)
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
                    .onSubmit { sendQuestion() }
                
                if chatService.isLoading {
                    Button(action: { chatService.stopGenerating() }) {
                        ZStack {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 38, height: 38)
                            Image(systemName: "stop.fill")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("응답 중지")
                } else {
                    Button(action: sendQuestion) {
                        ZStack {
                            Circle()
                                .fill(chatInput.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                                .frame(width: 38, height: 38)
                            Image(systemName: "arrow.up")
                                .font(.body.bold())
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(chatInput.isEmpty)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .frame(minWidth: 300)
    }
    
    private func quickActionIcon(for label: String) -> String {
        switch label {
        case "요약": return "doc.text"
        case "액션 아이템": return "checklist"
        case "결정 사항": return "checkmark.seal"
        default: return "sparkle"
        }
    }
    
    // MARK: - Bottom Controls
    private var bottomControls: some View {
        HStack(spacing: 16) {
            // Record Button
            Button(action: toggleRecording) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 32, height: 32)
                        
                        if store.state == .preparing || store.state == .stopping {
                            ProgressView()
                                .scaleEffect(0.7)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: store.state == .recording ? "stop.fill" : "mic.fill")
                                .font(.body.bold())
                        }
                    }
                    Text(recordButtonText)
                        .font(.body.weight(.semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: recordButtonColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(25)
                .shadow(color: recordButtonColors[0].opacity(0.4), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(store.state == .preparing || store.state == .stopping)
            
            Button(action: {
                store.clear()
                chatHistory.removeAll()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("Clear")
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(20)
            }
            .buttonStyle(.plain)
            .disabled(store.state == .recording)
            
            Spacer()
            
            // Transcribe Settings
            HStack(spacing: 16) {
                CompactSlider(label: "버퍼", value: $settings.audioBufferSize, options: [1024, 2048, 4096, 8192], labels: ["1K", "2K", "4K", "8K"], tooltip: "낮음: 빠른 반응, 끊김 가능\n높음: 안정적, 지연 증가")
                CompactSlider(label: "Stability", value: $settings.partialResultsStabilityIndex, options: [0, 1, 2, 3], labels: ["Off", "Low", "Med", "High"], tooltip: "낮음: 빠른 표시, 텍스트 자주 변경\n높음: 안정적 텍스트, 화자분리 정확도 저하")
                CompactSlider(label: "Sample", value: $settings.transcribeSampleRate, options: [8000, 16000, 32000], labels: ["8K", "16K", "32K"], tooltip: "낮음: 낮은 대역폭, 음질 저하\n높음: 고음질, 처리량 증가")
            }
            .disabled(store.state == .recording)
            .opacity(store.state == .recording ? 0.5 : 1)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
    
    private var recordButtonText: String {
        switch store.state {
        case .preparing: return "준비 중..."
        case .stopping: return "중지 중..."
        case .recording: return "녹음 중지"
        default: return "녹음 시작"
        }
    }
    
    private var recordButtonColors: [Color] {
        switch store.state {
        case .preparing, .stopping: return [.gray, .gray.opacity(0.7)]
        case .recording: return [.red, .orange]
        default: return [.blue, .purple]
        }
    }
    
    // MARK: - Settings Panel
    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(.linearGradient(colors: [.gray, .gray.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                                .frame(width: 32, height: 32)
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.white)
                        }
                        Text("Settings")
                            .font(.title2.bold())
                    }
                    Spacer()
                    Button(action: { showSettings = false }) {
                        Text("Done")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                
                SettingsCard(title: "AWS Credentials", icon: "key.fill", iconColor: .orange) {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsField(label: "Access Key") {
                            TextField("AKIA...", text: $settings.accessKey)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(8)
                        }
                        SettingsField(label: "Secret Key") {
                            SecureField("Secret Key", text: $settings.secretKey)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(8)
                        }
                        SettingsField(label: "Region (Transcribe)") {
                            Picker("", selection: $settings.region) {
                                Text("us-east-1").tag("us-east-1")
                                Text("us-west-2").tag("us-west-2")
                                Text("ap-northeast-2 (Seoul)").tag("ap-northeast-2")
                            }.labelsHidden()
                        }
                        
                        // Test connection button
                        HStack {
                            Button(action: { testCredentials() }) {
                                HStack(spacing: 6) {
                                    if isTestingCredentials {
                                        ProgressView().scaleEffect(0.7)
                                    } else {
                                        Image(systemName: "checkmark.shield")
                                    }
                                    Text("연결 테스트")
                                }
                                .font(.subheadline)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isTestingCredentials || !settings.isConfigured)
                            
                            if let result = credentialsTestResult {
                                Text(result)
                                    .font(.caption)
                                    .foregroundColor(result.contains("✓") ? .green : .red)
                            }
                        }
                        
                        Label("AI Chat uses us-east-1 (Bedrock)", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                SettingsCard(title: "AI Chat", icon: "bubble.left.and.bubble.right.fill", iconColor: .blue) {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsField(label: "Chat History Limit") {
                            Picker("", selection: $settings.chatHistoryLimit) {
                                Text("10 messages").tag(10)
                                Text("20 messages").tag(20)
                                Text("50 messages").tag(50)
                                Text("Unlimited").tag(999)
                            }.labelsHidden()
                        }
                        Label("More history = better context, but slower", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                SettingsCard(title: "System Prompt", icon: "text.alignleft", iconColor: .purple) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI에게 전달되는 기본 지시사항")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $settings.systemPrompt)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 120)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(8)
                    }
                }
                
                SettingsCard(title: "Quick Actions", icon: "bolt.fill", iconColor: .yellow) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(settings.quickPrompts.indices, id: \.self) { index in
                            HStack(spacing: 10) {
                                TextField("이름", text: $settings.quickPrompts[index].label)
                                    .textFieldStyle(.plain)
                                    .padding(8)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .cornerRadius(6)
                                    .frame(width: 80)
                                    .onChange(of: settings.quickPrompts[index].label) { _ in settings.saveQuickPrompts() }
                                TextField("프롬프트", text: $settings.quickPrompts[index].prompt)
                                    .textFieldStyle(.plain)
                                    .padding(8)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .cornerRadius(6)
                                    .onChange(of: settings.quickPrompts[index].prompt) { _ in settings.saveQuickPrompts() }
                                Button(action: { settings.deleteQuickPrompt(at: index) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red.opacity(0.7))
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Button(action: { settings.addQuickPrompt() }) {
                            Label("Add Button", systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                    }
                }
                
                Spacer()
            }
            .padding(4)
        }
    }
    
    // MARK: - Actions
    private func sendQuestion() {
        guard !chatInput.isEmpty else { return }
        let question = chatInput
        chatInput = ""
        
        chatHistory.append(ChatMessage(role: .user, content: question))
        let assistantMessage = ChatMessage(role: .assistant, content: "")
        chatHistory.append(assistantMessage)
        let assistantIndex = chatHistory.count - 1
        
        let historyForAPI = chatHistory.dropLast().map { msg in
            ChatHistoryItem(role: msg.role == .user ? "user" : "assistant", content: msg.content)
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
        transcribeService.lastError = nil
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
                
                // 스트림 종료 후 에러 확인
                await MainActor.run {
                    if let error = transcribeService.lastError {
                        store.state = .error(error)
                    } else if store.state == .recording {
                        store.state = .idle
                    }
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
    
    private func testCredentials() {
        isTestingCredentials = true
        credentialsTestResult = nil
        
        Task {
            let result = await settings.validateCredentials()
            await MainActor.run {
                credentialsTestResult = result.message
                isTestingCredentials = false
            }
        }
    }
}

// MARK: - Components

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    var content: String
    let timestamp = Date()
}

enum ChatRole { case user, assistant }

struct ChatBubble: View {
    let message: ChatMessage
    var onCopy: () -> Void = {}
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: message.timestamp)
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if message.role == .user { Spacer(minLength: 50) }
            
            if message.role == .assistant {
                ZStack {
                    Circle()
                        .fill(.linearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 28, height: 28)
                    Image(systemName: "sparkles")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                }
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.content.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(0..<3) { i in
                            Circle()
                                .fill(Color.gray)
                                .frame(width: 6, height: 6)
                                .opacity(0.5)
                        }
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(16)
                } else {
                    HStack(alignment: .top, spacing: 6) {
                        if message.role == .user { Spacer(minLength: 0) }
                        
                        Text(message.content)
                            .font(.system(.body, design: .rounded))
                            .textSelection(.enabled)
                            .padding(12)
                            .background(
                                message.role == .user
                                ? AnyShapeStyle(.linearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                : AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                            )
                            .foregroundColor(message.role == .user ? .white : .primary)
                            .cornerRadius(16)
                        
                        if message.role == .assistant && !message.content.isEmpty {
                            Button(action: onCopy) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("복사")
                        }
                    }
                }
                
                Text(timeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if message.role == .user {
                ZStack {
                    Circle()
                        .fill(.linearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 28, height: 28)
                    Image(systemName: "person.fill")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                }
            }
            
            if message.role == .assistant { Spacer(minLength: 50) }
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let disabled: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color.blue.opacity(0.2) : Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(8)
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

struct CompactSlider<T: Hashable>: View {
    let label: String
    @Binding var value: T
    let options: [T]
    let labels: [String]
    var tooltip: String = ""
    @State private var showTooltip = false
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                if !tooltip.isEmpty {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .onHover { showTooltip = $0 }
                        .popover(isPresented: $showTooltip, arrowEdge: .top) {
                            Text(tooltip)
                                .font(.caption)
                                .padding(12)
                                .frame(maxWidth: 200)
                        }
                }
            }
            
            HStack(spacing: 2) {
                ForEach(Array(zip(options.indices, options)), id: \.0) { index, option in
                    Button(labels[index]) { withAnimation(.easeOut(duration: 0.15)) { value = option } }
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(value == option ? Color.blue : Color.gray.opacity(0.15))
                        .foregroundColor(value == option ? .white : .secondary)
                        .cornerRadius(6)
                }
            }
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .foregroundColor(iconColor)
                }
                Text(title)
                    .font(.headline)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

struct SettingsField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
            content
        }
    }
}

// MARK: - Speaker Management

struct TranscriptRow: View {
    let speaker: String?
    let displayName: String?
    let text: String
    var timestamp: Date? = nil
    let color: Color
    var isPartial: Bool = false
    var searchTerm: String = ""
    
    private var timeString: String {
        guard let ts = timestamp else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: ts)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Timestamp
            if timestamp != nil {
                Text(timeString)
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 55, alignment: .leading)
            }
            
            // Speaker indicator
            if displayName != nil {
                VStack(spacing: 4) {
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)
                    Rectangle()
                        .fill(color.opacity(0.3))
                        .frame(width: 2)
                }
                .frame(width: 10)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let name = displayName {
                    Text(name)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(color)
                }
                
                if searchTerm.isEmpty {
                    Text(text)
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(isPartial ? .secondary : .primary)
                        .opacity(isPartial ? 0.7 : 1)
                } else {
                    HighlightedText(text: text, highlight: searchTerm)
                        .font(.system(.body, design: .rounded))
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

struct HighlightedText: View {
    let text: String
    let highlight: String
    
    var body: some View {
        highlightedAttributedText
    }
    
    private var highlightedAttributedText: some View {
        var result = Text("")
        var remaining = text[...]
        
        while let range = remaining.range(of: highlight, options: .caseInsensitive) {
            let before = remaining[..<range.lowerBound]
            let match = remaining[range]
            result = result + Text(before) + Text(match).bold().foregroundColor(.orange)
            remaining = remaining[range.upperBound...]
        }
        result = result + Text(remaining)
        return result
    }
}

struct SpeakerBar: View {
    @ObservedObject var store: TranscriptionStore
    
    private let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(store.detectedSpeakers.enumerated()), id: \.element) { index, speaker in
                    SpeakerChip(
                        speaker: speaker,
                        displayName: store.displayName(for: speaker),
                        color: colors[index % colors.count],
                        onRename: { newName in
                            store.renameSpeaker(speaker, to: newName)
                        }
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SpeakerChip: View {
    let speaker: String
    let displayName: String
    let color: Color
    let onRename: (String) -> Void
    
    @State private var isEditing = false
    @State private var editName = ""
    
    var body: some View {
        Button(action: { 
            editName = displayName == speaker ? "" : displayName
            isEditing = true 
        }) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(displayName)
                    .font(.caption.weight(.medium))
                Image(systemName: "pencil")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isEditing) {
            VStack(spacing: 10) {
                Text("화자 이름 변경")
                    .font(.subheadline.weight(.semibold))
                TextField(speaker, text: $editName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .onSubmit {
                        onRename(editName)
                        isEditing = false
                    }
                HStack {
                    Button("취소") { isEditing = false }
                        .buttonStyle(.plain)
                    Button("저장") {
                        onRename(editName)
                        isEditing = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
        }
    }
}


// MARK: - Error Toast

struct ErrorToast: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("오류 발생")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .frame(maxWidth: 400)
    }
}

// MARK: - Onboarding Overlay

struct OnboardingOverlay: View {
    let onOpenSettings: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Image(systemName: "key.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.linearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                Text("AWS 자격 증명 필요")
                    .font(.title2.bold())
                
                Text("Meeting Helper를 사용하려면\nAWS Access Key와 Secret Key가 필요합니다.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button(action: onOpenSettings) {
                    HStack {
                        Image(systemName: "gearshape.fill")
                        Text("설정으로 이동")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            .padding(40)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        }
    }
}
