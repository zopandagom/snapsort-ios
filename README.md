# SnapSort

온디바이스 AI로 사진 보관함의 이미지를 자동 분류·정리하는 iOS 앱.
출시 앱에서 사진과 사진에서 읽은 텍스트는 기기 밖으로 나가지 않는다 (장소 이름·지도 표시를 위한 위치 좌표와 언어·지역 설정만 Apple 시스템 서비스 사용(사용자가 지도를 움직이면 그 영역도), 사용자가 누를 때만 읽은 주소를 지도 앱으로 넘김). [개인정보 처리방침](https://zopandagom.github.io/snapsort-ios/privacy/) (본문 [`site/privacy/index.html`](site/privacy/index.html)).

## 핵심 기능 (MVP)
- 전체 이미지 자동 분류 (한 장이 여러 카테고리에 속할 수 있음)
  - 정보형: 기프티콘 / 영수증 / 대화 캡처 / 쇼핑 / 지도 / 문서·메모
  - 사진형: 여행 / 음식 / 인물 / 반려동물 / 풍경
  - 기타
- 카테고리마다 맞는 기준으로 묶기: 기프티콘은 만료 임박순, 영수증은 가게별·월 합계, 쇼핑은 쇼핑몰·브랜드별, 대화 캡처는 앱별, 지도는 지역별, 여행은 여행 단위 폴더 등
- 여행 폴더에 그 기간의 캡처(항공권·예약·영수증·지도)를 함께 모으기
- 정리 도우미: 지난 것 정리 추천, 비슷한 이미지 묶기, 확보 용량 표시 + 일괄 삭제, 최근 스크린샷 한 장씩 보관·삭제
- 캡처를 행동으로: 기프티콘 바코드 크게 보기, 주소 → 지도 앱, 송장·계좌번호 복사
- 기프티콘 만료일 추출 + 로컬 알림
- 분류와 이어진 기기 안 검색: 사진 속 글자에 더해 쇼핑몰·브랜드·대화 앱·지역 이름, 카테고리·여행 장소로 바로 이동, 결과에서 바로 캡처 행동
- 보관함 홈 "곧 만료" 띠: 7일 안에 만료되는 기프티콘을 썸네일·D-day 로 모아 보고, 눌러 바로 바코드
- 홈·잠금 화면 만료 임박 위젯: 7일 안에 만료되는 기프티콘 수와 가장 가까운 D-day

## 기술 스택
- SwiftUI (규칙 기반 단방향 MV), Swift 6 strict concurrency
- PhotoKit, Vision (이미지 분류·OCR·바코드·유사 이미지), Foundation Models (Apple Intelligence 기기), SwiftData
- MapKit (지도 표시·장소 이름 변환, 위치 좌표와 언어·지역 설정만 Apple 로 전송, 사용자가 지도를 움직이면 그 영역도)
- WidgetKit
- Tuist 모듈러 아키텍처 (Feature / Client Interface·Impl·Testing)

## 시작하기
`.mise.toml`·`Gemfile` 이 바뀌면(fastlane 추가 전에 만든 환경 포함) `make bootstrap` 을 다시 돌린다.
```bash
make bootstrap   # mise 로 tuist·swiftlint·swiftformat·xcbeautify·Ruby 설치, bundle install 로 fastlane 설치, git 훅(pre-commit: main 커밋 차단·lint, pre-merge-commit: main 머지 커밋 차단, pre-push: main push 차단) 연결
make generate    # SnapSort.xcworkspace 생성 후 Xcode 로 열기
make test        # 전체 모듈 빌드 + 테스트 + git 훅 테스트 + 출시 태그 검사 테스트
make test-hooks  # git 훅 동작 테스트만 (임시 레포에서 main 커밋·머지 커밋·push 차단과 기능 브랜치 통과 확인)
make test-release-tag # 출시 태그 검사 스크립트 테스트만 (vX.Y.Z 형식, 태그 커밋이 main 에 있는지)
make lint        # 포맷·아키텍처 규칙 검사 (make format 으로 자동 수정)
make lanes       # fastlane lane 목록 (Gemfile·Fastfile 이 읽히는지 확인)
make test-scripts                 # scripts/ 개발 스크립트 테스트
make mask-samples FILE=<초안.json> # 분류 샘플 초안의 OCR 줄 가리기 (docs/CONVENTIONS.md §3)
RELEASE_VERSION=1.0.0 RELEASE_BUILD_NUMBER=1 make release-ipa # 출시 빌드 archive + export 만 (업로드 없음)
```

## 출시
main 에 머지된 커밋에 `vX.Y.Z` 태그를 push 하면 GitHub Actions(`.github/workflows/release.yml`)가 fastlane 으로 App Store Connect 에 빌드·메타데이터(`fastlane/metadata/ko`)를 올리고 심사 제출하며, 통과하면 자동 공개한다. 레포 Secrets `ASC_KEY_ID`·`ASC_ISSUER_ID`·`ASC_KEY_P8`(App Store Connect API 키 `.p8` 의 base64)이 필요하다. 규칙·리허설·실패 시 다시 시도는 [CONVENTIONS §5 태그 출시](docs/CONVENTIONS.md), 서명·버전은 [ARCHITECTURE §2 빌드 설정](docs/ARCHITECTURE.md).

## 문서
- [아키텍처](docs/ARCHITECTURE.md)
- [개발 규칙: 해야 할 것 / 하지 말아야 할 것](docs/CONVENTIONS.md)
- [개발 계획과 로드맵](docs/DEVELOPMENT_PLAN.md)
- [Claude Code 작업 안내](CLAUDE.md)
