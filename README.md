# Meeting Helper

Real-time meeting transcription and AI assistant for macOS.

## Features

- 🎙️ Real-time audio recording (microphone + system audio)
- 📝 Live transcription via AWS Transcribe
- 👥 Speaker diarization
- 🤖 AI assistant powered by Claude (AWS Bedrock)
- ⚡ Quick actions (summary, action items, decisions)

## Requirements

- macOS 13.0+
- AWS account with Transcribe and Bedrock access

## Installation

### Homebrew (Recommended)
```bash
brew tap kcrong/mytap
brew install --cask meeting-helper
```

### Manual
1. Download the latest DMG from [Releases](../../releases/latest)
2. Open DMG → Drag MeetingHelper to Applications
3. First launch: Right-click → Open (to bypass Gatekeeper)

## Setup

1. Launch the app and click Settings
2. Enter your AWS Access Key and Secret Key
3. Select your preferred region for Transcribe
4. Click "Test Connection" to verify credentials
