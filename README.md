# Meeting Helper

실시간 회의 녹음 및 AI 기반 트랜스크립션 macOS 앱

## 기능

- 🎙️ 실시간 음성 녹음 (마이크 + 시스템 오디오)
- 📝 AWS Transcribe를 이용한 실시간 트랜스크립션
- 👥 화자 분리 (Speaker Diarization)
- 🤖 AI 어시스턴트 (Claude via AWS Bedrock)
- ⚡ Quick Actions (요약, 액션 아이템, 결정 사항)

## 요구사항

- macOS 13.0+
- AWS 계정 (Transcribe + Bedrock 접근 권한)

## 설치

1. [Releases](../../releases/latest)에서 최신 DMG 다운로드
2. DMG 열기 → MeetingHelper를 Applications로 드래그
3. 첫 실행 시: 우클릭 → 열기 (Gatekeeper 우회)

## 설정

1. 앱 실행 후 Settings 클릭
2. AWS Access Key / Secret Key 입력
3. Region 선택 (Transcribe용)

## 빌드

```bash
# Xcode로 열기
open MeetingHelper.xcodeproj

# 또는 커맨드라인 빌드
xcodebuild -scheme MeetingHelper -configuration Release
```

## 라이선스

MIT
