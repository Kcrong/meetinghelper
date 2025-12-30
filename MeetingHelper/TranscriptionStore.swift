import SwiftUI

@MainActor
class TranscriptionStore: ObservableObject {
    @Published var segments: [TranscriptionSegment] = []
    @Published var partialText = ""
    @Published var partialSpeaker: String? = nil
    @Published var state: SessionState = .idle
    @Published var speakerNames: [String: String] = [:] // spk_0 -> "John"
    
    private var currentSpeaker: String? = nil
    
    var detectedSpeakers: [String] {
        let speakers = Set(segments.compactMap { $0.speaker })
        return speakers.sorted()
    }
    
    func displayName(for speaker: String) -> String {
        speakerNames[speaker] ?? speaker
    }
    
    func renameSpeaker(_ speaker: String, to name: String) {
        speakerNames[speaker] = name.isEmpty ? nil : name
    }
    
    func appendResult(_ result: TranscriptionResult) {
        if result.isPartial {
            partialText = result.text
            partialSpeaker = result.speakerLabel
        } else {
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
        speakerNames = [:]
    }
    
    var displayText: String {
        var text = segments.map { segment in
            if let speaker = segment.speaker {
                return "[\(displayName(for: speaker))] \(segment.text)"
            }
            return segment.text
        }.joined(separator: "\n")
        
        if !partialText.isEmpty {
            if let speaker = partialSpeaker {
                text += "\n[\(displayName(for: speaker))] \(partialText)"
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
