# SnapSort

온디바이스 AI로 사진 보관함의 이미지를 자동 분류·정리하는 iOS 앱.
사진은 기기 밖으로 나가지 않는다.

## 핵심 기능 (MVP)
- 전체 이미지 자동 분류 (한 장이 여러 카테고리에 속할 수 있음)
  - 정보형: 기프티콘 / 영수증 / 대화 캡처 / 쇼핑 / 지도 / 문서·메모
  - 사진형: 여행 / 음식 / 인물 / 반려동물 / 풍경
  - 기타
- 카테고리마다 맞는 기준으로 묶기: 기프티콘은 만료 임박순, 영수증은 가게별·월 합계, 여행은 여행 단위 폴더 등
- 여행 폴더에 그 기간의 캡처(항공권·예약·영수증·지도)를 함께 모으기
- 정리 도우미: 지난 것 정리 추천, 비슷한 스크린샷 묶기, 확보 용량 표시 + 일괄 삭제, 캡처 인박스
- 캡처를 행동으로: 기프티콘 바코드 크게 보기, 주소 → 지도 앱, 송장·계좌번호 복사
- 기프티콘 만료일 추출 + 로컬 알림
- OCR 전문 검색
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
