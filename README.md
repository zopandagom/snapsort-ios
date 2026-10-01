# SnapSort

온디바이스 AI로 스크린샷을 자동 정리하는 iOS 앱.
사진은 기기 밖으로 나가지 않는다.

## 핵심 기능 (MVP)
- 스크린샷 자동 분류: 영수증 / 기프티콘 / 대화 캡처 / 쇼핑 / 지도 / 기타
- 기프티콘 만료일 추출 + 로컬 알림
- OCR 전문 검색, 일괄 삭제
- 홈 화면 위젯

## 기술 스택
- SwiftUI (규칙 기반 단방향 MV), Swift 6 strict concurrency
- PhotoKit, Vision (OCR), Foundation Models (Apple Intelligence 기기), SwiftData
- WidgetKit, StoreKit 2
- Tuist 모듈러 아키텍처 (Feature / Client Interface·Impl·Testing)

## 시작하기
```bash
make bootstrap   # mise 로 tuist·swiftlint·swiftformat·xcbeautify 설치, git 훅(pre-commit lint, pre-push main 차단) 연결
make generate    # SnapSort.xcworkspace 생성
make test        # 전체 모듈 빌드 + 테스트
make lint        # 포맷·아키텍처 규칙 검사 (make format 으로 자동 수정)
```

## 문서
- [아키텍처](docs/ARCHITECTURE.md)
- [개발 규칙: 해야 할 것 / 하지 말아야 할 것](docs/CONVENTIONS.md)
- [개발 계획과 로드맵](docs/DEVELOPMENT_PLAN.md)
- [Claude Code 작업 안내](CLAUDE.md)
