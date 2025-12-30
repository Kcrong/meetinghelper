import Foundation

struct TranscriptionResult {
    let text: String
    let isPartial: Bool
    let timestamp: Date
    let speakerLabel: String?  // 화자 분리용
}

struct AudioSettings {
    static let sampleRate: Double = 16000
    static let channels: UInt32 = 1
    static let bitsPerSample: UInt32 = 16
}

struct AWSCredentials {
    var accessKey: String
    var secretKey: String
    var region: String
    
    var isValid: Bool {
        !accessKey.isEmpty && !secretKey.isEmpty && !region.isEmpty
    }
}

enum SessionState: Equatable {
    case idle
    case preparing
    case recording
    case stopping
    case error(String)
}
