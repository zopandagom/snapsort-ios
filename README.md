# SnapSort

온디바이스 AI로 스크린샷을 자동 정리하는 iOS 앱.
사진은 기기 밖으로 나가지 않는다.

## 핵심 기능 (MVP)
- 스크린샷 자동 분류: 영수증 / 기프티콘 / 대화 캡처 / 쇼핑 / 지도 / 기타
- 기프티콘 만료일 추출 + 로컬 알림
- OCR 전문 검색, 일괄 삭제
- 홈 화면 위젯

## 기술 스택
- SwiftUI, SwiftData, Swift 6 (strict concurrency)
- PhotoKit, Vision (OCR), Foundation Models (Apple Intelligence 기기)
- WidgetKit, StoreKit 2
- Tuist

## 분류 파이프라인
1. PhotoKit `mediaSubtypes` 필터로 스크린샷만 조회
2. Vision OCR → 키워드 규칙 기반 1차 분류 (모든 기기)
3. Foundation Models `@Generable` 구조화 추출 (Apple Intelligence 지원 기기만)

## 시작하기
```bash
mise install          # tuist 설치
tuist generate
```

## 로드맵
| 주차 | 목표 |
|---|---|
| 1 | 프로젝트 뼈대, CI, 사진 권한, 스크린샷 조회 |
| 2 | OCR + 규칙 기반 분류 파이프라인, SwiftData 저장 |
| 3 | Foundation Models 분류, 기프티콘 추출, 만료 알림 |
| 4 | 메인 UI, 검색, 일괄 삭제, 위젯 |
| 5 | StoreKit 2 결제, 온보딩, TestFlight |
| 6 | ASO, 스토어 에셋, 출시 |
