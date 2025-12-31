cask "meeting-helper" do
  version "2025.12.31-7b262f1"
  sha256 "0402d8a93665c0ddb3df77ab5aad88ebe55ffab1dfa83b2eeb6de168e8cba201"

  url "https://github.com/kcrong/meetinghelper/releases/download/v#{version}/MeetingHelper.dmg"
  name "Meeting Helper"
  desc "Real-time meeting transcription with AI assistant"
  homepage "https://github.com/kcrong/meetinghelper"

  depends_on macos: ">= :ventura"

  app "MeetingHelper.app"

  zap trash: [
    "~/Library/Preferences/com.example.MeetingHelper.plist",
  ]
end
