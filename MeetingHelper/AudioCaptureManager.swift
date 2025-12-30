import AVFoundation
import ScreenCaptureKit

@MainActor
class AudioCaptureManager: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var scStream: SCStream?
    private var streamOutput: AudioStreamOutput?
    private var continuation: AsyncStream<Data>.Continuation?
    
    @Published var isCapturing = false
    
    func startCapture() async throws -> AsyncStream<Data> {
        let stream = AsyncStream<Data> { continuation in
            self.continuation = continuation
        }
        
        try await startMicrophoneCapture()
        
        do {
            try await startSystemAudioCapture()
            print("✅ [Audio] System audio capture started")
        } catch {
            print("⚠️ [Audio] System audio not available: \(error.localizedDescription)")
        }
        
        isCapturing = true
        return stream
    }
    
    func stopCapture() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        
        if let scStream {
            Task { try? await scStream.stopCapture() }
        }
        scStream = nil
        streamOutput = nil
        continuation?.finish()
        continuation = nil
        isCapturing = false
        print("🛑 [Audio] Capture stopped")
    }
    
    private func startMicrophoneCapture() async throws {
        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("🎤 [Audio] Microphone format: \(inputFormat)")
        
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * 16000 / inputFormat.sampleRate)
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }
            
            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            if let data = convertedBuffer.int16Data() {
                self.continuation?.yield(data)
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        print("✅ [Audio] Microphone capture started")
    }
    
    private func startSystemAudioCapture() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw AudioCaptureError.noDisplayFound
        }
        
        let excludedApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])
        
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000  // ScreenCaptureKit 기본값 사용
        config.channelCount = 2
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        self.scStream = stream
        
        let output = AudioStreamOutput { [weak self] data in
            self?.continuation?.yield(data)
        }
        self.streamOutput = output
        
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream.startCapture()
    }
}

private class AudioStreamOutput: NSObject, SCStreamOutput {
    let handler: (Data) -> Void
    private var chunkCount = 0
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    
    init(handler: @escaping (Data) -> Void) {
        self.handler = handler
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let pcmBuffer = sampleBuffer.toPCMBuffer() else { return }
        
        // 컨버터 초기화 (최초 1회)
        if converter == nil {
            converter = AVAudioConverter(from: pcmBuffer.format, to: targetFormat)
            print("🔊 [Audio] System audio format: \(pcmBuffer.format)")
        }
        
        guard let converter else { return }
        
        // 변환
        let frameCount = AVAudioFrameCount(Double(pcmBuffer.frameLength) * 16000 / pcmBuffer.format.sampleRate)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }
        
        var error: NSError?
        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return pcmBuffer
        }
        
        if let data = convertedBuffer.int16Data() {
            handler(data)
            
            chunkCount += 1
            if chunkCount % 100 == 0 {
                print("🔊 [Audio] System audio chunks: \(chunkCount), bytes: \(data.count)")
            }
        }
    }
}

private extension CMSampleBuffer {
    func toPCMBuffer() -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(self),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return nil }
        
        guard let format = AVAudioFormat(streamDescription: asbd) else { return nil }
        
        let frameCount = CMSampleBufferGetNumSamples(self)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        
        guard let blockBuffer = CMSampleBufferGetDataBuffer(self) else { return nil }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        
        guard let dataPointer, let floatData = buffer.floatChannelData else { return nil }
        
        // Float32 데이터 복사
        let srcPtr = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Float.self)
        let channels = Int(format.channelCount)
        let frames = frameCount
        
        if format.isInterleaved {
            for frame in 0..<frames {
                for ch in 0..<channels {
                    floatData[ch][frame] = srcPtr[frame * channels + ch]
                }
            }
        } else {
            memcpy(floatData[0], srcPtr, length)
        }
        
        return buffer
    }
}

private extension AVAudioPCMBuffer {
    func int16Data() -> Data? {
        guard let channelData = int16ChannelData else { return nil }
        return Data(bytes: channelData[0], count: Int(frameLength) * MemoryLayout<Int16>.size)
    }
}

enum AudioCaptureError: Error, LocalizedError {
    case converterCreationFailed, noDisplayFound
    var errorDescription: String? {
        switch self {
        case .converterCreationFailed: return "오디오 변환기 생성 실패"
        case .noDisplayFound: return "디스플레이를 찾을 수 없음"
        }
    }
}
