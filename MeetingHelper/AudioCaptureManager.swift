import AVFoundation
import ScreenCaptureKit
import CoreAudio

enum AudioInputMode: String, CaseIterable {
    case both = "Mic + System"
    case micOnly = "Mic Only"
    case systemOnly = "System Only"
}

@MainActor
class AudioCaptureManager: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var scStream: SCStream?
    private var streamOutput: AudioStreamOutput?
    private var continuation: AsyncStream<Data>.Continuation?
    
    @Published var isCapturing = false
    @Published var availableMicrophones: [AVCaptureDevice] = []
    @Published var selectedMicrophoneID: String?
    
    var hasExternalMicrophone: Bool {
        availableMicrophones.contains { !$0.localizedName.contains("MacBook") && !$0.localizedName.contains("Built-in") }
    }
    
    func refreshMicrophones() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        availableMicrophones = session.devices
        
        // Auto-select external mic if available
        if let external = availableMicrophones.first(where: { !$0.localizedName.contains("MacBook") && !$0.localizedName.contains("Built-in") }) {
            selectedMicrophoneID = external.uniqueID
            print("[MH-AUDIO] External mic selected: \(external.localizedName)")
        } else if selectedMicrophoneID == nil, let first = availableMicrophones.first {
            selectedMicrophoneID = first.uniqueID
        }
        
        print("[MH-AUDIO] Available mics: \(availableMicrophones.map { $0.localizedName })")
    }
    
    /// Returns true if no microphone available
    var shouldUseSystemOnly: Bool {
        availableMicrophones.isEmpty
    }
    
    var bufferSize: Int = 4096
    
    func startCapture(mode: AudioInputMode = .both) async throws -> AsyncStream<Data> {
        refreshMicrophones()
        
        // Auto switch to system-only if no mic
        let effectiveMode = shouldUseSystemOnly ? .systemOnly : mode
        if effectiveMode != mode {
            print("[MH-AUDIO] No microphone available, switching to system-only mode")
        }
        
        let stream = AsyncStream<Data> { continuation in
            self.continuation = continuation
        }
        
        if effectiveMode == .micOnly || effectiveMode == .both {
            try await startMicrophoneCapture()
        }
        
        if effectiveMode == .systemOnly || effectiveMode == .both {
            do {
                try await startSystemAudioCapture()
                print("[MH-AUDIO] System audio capture started")
            } catch {
                print("[MH-AUDIO] System audio not available: \(error.localizedDescription)")
            }
        }
        
        print("[MH-AUDIO] Capture mode: \(effectiveMode.rawValue), bufferSize: \(bufferSize)")
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
        print("[MH-AUDIO] Capture stopped")
    }
    
    private func startMicrophoneCapture() async throws {
        // Set selected mic as system default input
        if let micID = selectedMicrophoneID,
           let device = availableMicrophones.first(where: { $0.uniqueID == micID }) {
            setSystemDefaultInput(deviceUID: micID)
            print("[MH-AUDIO] Using microphone: \(device.localizedName)")
        }
        
        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("[MH-AUDIO] Microphone format: \(inputFormat)")
        
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }
        
        inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(bufferSize), format: inputFormat) { [weak self] buffer, _ in
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
        print("[MH-AUDIO] Microphone capture started")
    }
    
    private func setSystemDefaultInput(deviceUID: String) {
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceCount: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &deviceCount)
        let count = Int(deviceCount) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &deviceCount, &devices)
        
        for device in devices {
            var uid: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, &uid)
            
            if uid as String == deviceUID {
                deviceID = device
                break
            }
        }
        
        if deviceID != 0 {
            var defaultAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, 0, nil, size, &deviceID)
        }
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
        config.sampleRate = 48000  // ScreenCaptureKit default
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
        
        // Initialize converter once
        if converter == nil {
            converter = AVAudioConverter(from: pcmBuffer.format, to: targetFormat)
            print("🔊 [Audio] System audio format: \(pcmBuffer.format)")
        }
        
        guard let converter else { return }
        
        // Convert
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
        
        // Copy Float32 data
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
        case .converterCreationFailed: return "Failed to create audio converter"
        case .noDisplayFound: return "No display found"
        }
    }
}
