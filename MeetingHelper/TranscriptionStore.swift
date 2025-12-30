import SwiftUI

@MainActor
class TranscriptionStore: ObservableObject {
    @Published var segments: [TranscriptionSegment] = []
    @Published var partialText = ""
    @Published var partialSpeaker: String? = nil
    @Published var state: SessionState = .idle
    
    private var currentSpeaker: String? = nil
    
    func appendResult(_ result: TranscriptionResult) {
        if result.isPartial {
            partialText = result.text
            partialSpeaker = result.speakerLabel
        } else {
            // 같은 화자면 기존 세그먼트에 추가, 다르면 새 세그먼트
            if let speaker = result.speakerLabel, speaker == currentSpeaker, !segments.isEmpty {
                segments[segments.count - 1].text += " " + result.text
            } else {
                segments.append(TranscriptionSegment(
                    speaker: result.speakerLabel,
                    text: result.text,
                    timestamp: result.timestamp
                ))
                currentSpeaker = result.speakerLabel
            }
            partialText = ""
            partialSpeaker = nil
        }
    }
    
    func clear() {
        segments = []
        partialText = ""
        partialSpeaker = nil
        currentSpeaker = nil
    }
    
    var displayText: String {
        var text = segments.map { segment in
            if let speaker = segment.speaker {
                return "[\(speaker)] \(segment.text)"
            }
            return segment.text
        }.joined(separator: "\n")
        
        if !partialText.isEmpty {
            if let speaker = partialSpeaker {
                text += "\n[\(speaker)] \(partialText)"
            } else {
                text += "\n\(partialText)"
            }
        }
        return text
    }
}

struct TranscriptionSegment: Identifiable {
    let id = UUID()
    var speaker: String?
    var text: String
    let timestamp: Date
}
