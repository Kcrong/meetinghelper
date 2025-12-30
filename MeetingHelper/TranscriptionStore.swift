import SwiftUI

@MainActor
class TranscriptionStore: ObservableObject {
    @Published var transcriptionText = ""
    @Published var partialText = ""
    @Published var state: SessionState = .idle
    
    func appendResult(_ result: TranscriptionResult) {
        if result.isPartial {
            partialText = result.text
        } else {
            transcriptionText += result.text + " "
            partialText = ""
        }
    }
    
    func clear() {
        transcriptionText = ""
        partialText = ""
    }
    
    var displayText: String {
        transcriptionText + partialText
    }
}
