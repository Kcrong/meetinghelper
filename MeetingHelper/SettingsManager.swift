import SwiftUI

class SettingsManager: ObservableObject {
    @AppStorage("accessKey") var accessKey = ""
    @AppStorage("secretKey") var secretKey = ""
    @AppStorage("region") var region = "us-east-1"
    @AppStorage("language") var language = "ko-KR"
    
    var credentials: AWSCredentials {
        AWSCredentials(accessKey: accessKey, secretKey: secretKey, region: region)
    }
    
    var isConfigured: Bool {
        credentials.isValid
    }
}
