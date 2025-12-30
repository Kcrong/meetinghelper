import SwiftUI

struct ContentView: View {
    @StateObject private var store = TranscriptionStore()
    @StateObject private var audioManager = AudioCaptureManager()
    @StateObject private var transcribeService = TranscribeService()
    @StateObject private var settings = SettingsManager()
    
    @State private var showSettings = false
    
    var body: some View {
        VStack(spacing: 16) {
            if showSettings {
                settingsPanel
            } else {
                mainPanel
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
    
    private var mainPanel: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Meeting Helper")
                    .font(.title2.bold())
                Spacer()
                Button("Settings") { showSettings = true }
            }
            
            ScrollView {
                Text(store.displayText.isEmpty ? "트랜스크립션이 여기에 표시됩니다..." : store.displayText)
                    .foregroundColor(store.displayText.isEmpty ? .gray : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
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
                
                Button("Clear") { store.clear() }
                    .disabled(store.state == .recording)
            }
            
            if case .error(let message) = store.state {
                Text(message)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
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
                    
                    Text("Region")
                        .font(.caption)
                    Picker("", selection: $settings.region) {
                        Text("us-east-1").tag("us-east-1")
                        Text("us-west-2").tag("us-west-2")
                        Text("ap-northeast-2 (Seoul)").tag("ap-northeast-2")
                    }
                    .labelsHidden()
                }
                .padding(.vertical, 4)
            }
            
            GroupBox("Transcription") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Language")
                        .font(.caption)
                    Picker("", selection: $settings.language) {
                        Text("한국어").tag("ko-KR")
                        Text("English (US)").tag("en-US")
                        Text("日本語").tag("ja-JP")
                    }
                    .labelsHidden()
                }
                .padding(.vertical, 4)
            }
            
            Spacer()
        }
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
        print("🚀 [App] Starting recording with region: \(settings.region), language: \(settings.language)")
        
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
