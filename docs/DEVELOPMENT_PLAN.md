# 개발 계획

## 목표
- **제품:** 사진 보관함의 이미지를 기기 안에서 자동 분류하고(정보형·사진형 카테고리), 기프티콘 만료일을 찾아 알려주는 앱.
- **시장 목표:** 한국 App Store 유료 차트 또는 카테고리(생산성·유틸리티) 1위.
- **출시 목표:** 2026-11-11 (6주, 풀타임).

## 사진 앱과의 차별 기능 (MVP)
iOS 사진 앱도 기기 안에서 "여행", "음식" 검색과 여행 추억을 제공한다. 그래서 차별점은 사진 앱이 하지 않는 **카테고리별 묶음, 정리, 카테고리를 가로지르는 연결, 캡처에서 바로 행동, 분류와 이어진 검색**에 둔다. 사진 앱도 사진 속 글자(라이브 텍스트)를 찾으므로 검색의 차별점은 글자 검색 자체가 아니라 분류 결과와의 연결이다.

| 영역 | 기능 | 기술 메모 |
|---|---|---|
| 카테고리별 묶음 | 모든 카테고리는 월별 섹션이 기본. 추가 기준: 기프티콘 만료 임박순·사용함/미사용, 영수증 가게별 + 월 합계 금액, 여행 여행 단위 폴더, 쇼핑 브랜드·쇼핑몰별, 대화 캡처 앱별, 지도 지역별(기기 안 한국 행정구역 목록 대조) | 저장 모델은 지금 계산되는 값만 둔다: 월별은 생성일, 여행 폴더는 여행 판정 결과, 지도 지역별은 추출 값. 기프티콘 만료일·교환처는 추출 값으로 저장하고(만료 임박순 조회는 `PhotoStoreClient.upcomingGifticonExpiries(from:)`), 사용 여부는 사용자가 바꾸는 필드로 저장한다(`setGifticonUsed`, 사용한 기프티콘은 알리지 않는다). 영수증 가게·금액·통화·취소 여부는 추출 값으로 저장하고(규칙 버전, 영수증 목록 조회는 `PhotoStoreClient.receipts()`, 월 합계의 월은 생성일), 쇼핑몰·브랜드·대화 앱·지역은 추출 값(닫힌 목록 식별자, 규칙 버전, 목록 조회는 `PhotoStoreClient.captureGroupItems(in:)`)으로 저장한다 (ARCHITECTURE §4 저장소). 지도 위 핀은 Out 이다: 스크린샷에는 촬영 좌표가 없고, OCR 로 읽은 지역의 중심 좌표로 지도를 띄우면 OCR 유래 좌표·집 근처 타일 요청이 Apple 로 가므로 하지 않는다 |
| 카테고리 연결 | 여행 폴더에 그 기간의 캡처(항공권·숙소 예약·영수증·지도 캡처)를 함께 모은다 | 여행 판정(위치·날짜) 결과의 기간으로 다른 카테고리 이미지를 묶음. 관계로 저장하지 않고 조회할 때 기간으로 찾는다 |
| 정리 도우미 | 지난 것 정리 추천(만료된 기프티콘, 지난 탑승권·예약, 배송 끝난 송장), 비슷한 이미지 묶기, "N장 정리하면 X GB 확보" + 일괄 삭제, 최근 스크린샷(새 캡처를 한 장씩 보관/삭제) | 비슷한 이미지는 Vision 특징 벡터(`VNGenerateImageFeaturePrintRequest`) 거리. 삭제는 `PHAssetChangeRequest.deleteAssets`. 확보 용량은 픽셀 수 × 계수의 추정치로 표시하고(임시 계수는 실기기에서 조정), 지운 사진은 '최근 삭제된 항목'에 30일 남으므로 비우면 확보된다고 안내. 제한 접근이면 고른 사진 안에서만 정리하고 화면에 안내. 구현됨: 만료된·사용한 기프티콘 정리, 비슷한 사진 묶기(연속 촬영 카메라 사진. 기준값은 임시로 실기기에서 조정, 시뮬레이터는 벡터를 만들지 않아 섹션 없음), 최근 스크린샷(보관함 "정리 도우미" 카드). 남은 것: 지난 탑승권·예약·송장 |
| 캡처를 행동으로 | 기프티콘 바코드 크게 보기(화면 밝기 최대), 주소 → 지도 앱 열기, 송장·계좌번호 복사 | 바코드는 Vision `DetectBarcodesRequest` 로 읽어 QR·Code128·PDF417·Aztec 이고 내용이 ASCII 면 Core Image 로 다시 그리고, 그 밖은 원본의 바코드 영역을 확대(Core `BarcodeImageRenderer`). 주소·번호는 저장된 OCR 줄에서 추출(Core `CaptureInfoExtractor`). 추출 값은 저장하지 않고 열 때 찾는다. 주소는 문자열 그대로 지도 앱에 넘기고(Map Client, 앱이 지오코딩하지 않음), 번호는 이 기기에서만 붙여 넣게 복사한다(Pasteboard Client) (ARCHITECTURE §4 캡처 정보 추출) |
| 분류와 이어진 검색 | 사진 속 글자에 더해 닫힌 목록 별칭으로 쇼핑몰·브랜드·대화 앱·지역을 찾고("coupang" → 쿠팡 캡처, "서울" → 강남구만 읽힌 지도 캡처), 카테고리 이름·캐시된 여행 장소 이름으로 카테고리 화면·여행 폴더로 바로 가며, 맞은 줄을 보이고 결과 사진에서 바로 캡처 행동(주소 → 지도 앱, 번호 복사)을 한다 | 저장된 OCR 줄·추출 값·장소 캐시만 대조한다(OCR·지오코딩을 다시 하지 않음). `PhotoStoreClient.searchEntries()` + 메모리 색인(Core `SearchIndex`), 기기 안에서만 처리하고 Spotlight 색인·최근 검색어를 남기지 않는다 (ARCHITECTURE §4 검색) |

### 출시 후 후보
- 일정 캡처 → 캘린더에 추가 (EventKit)

## 로드맵
| 주차 | 기간 | 목표 | 완료 기준 |
|---|---|---|---|
| 0 | 9/30 | 모듈러 아키텍처, CI, 하네스, 문서 | 이 문서 세트 머지, CI 통과 |
| 1 | 10/1 – 10/7 | 사진 권한 온보딩 + 이미지 조회 | 전체/제한/거부 흐름, 신규 이미지 감지, Onboarding Feature |
| 2 | 10/8 – 10/14 | Vision 이미지 분류 + OCR + 규칙 기반 분류, 여행 판정, SwiftData 저장 | ImageAnalysis·PhotoStore·Indexing Client, Core 모듈, 픽스처 정확도 테스트 |
| 3 | 10/15 – 10/21 | Foundation Models 분류 + 기프티콘 추출, 만료 알림, 캡처 정보 추출(바코드·주소·송장·계좌) | Classifier·Notification Client, 미지원 기기 폴백 |
| 4 | 10/22 – 10/28 | 메인 UI(카테고리별 묶음, 여행 폴더), 검색, 정리 도우미, 위젯 | DesignSystem, 위젯 익스텐션(App Group) |
| 5 | 10/29 – 11/4 | 온보딩 마감(첫 화면 소개·개인정보 약속, 복귀 시 권한 다시 읽기, 제한(restricted) 안내) | Onboarding 확장. 무료 앱이라 결제 없음, TestFlight 외부 배포 안 함 |
| 6 | 11/5 – 11/11 | ASO, 스토어 에셋, 출시 | 심사 제출 |

### 주차별 예상 모듈
| 주차 | 새 Client | 새 Feature / Shared |
|---|---|---|
| 1 | (PhotoLibrary 확장: 변경 감지, 제한 접근 선택) | Onboarding |
| 2 | ImageAnalysis(Vision 이미지 분류·OCR), PhotoStore(SwiftData), Indexing(증분 인덱서), (PhotoLibrary 확장: 위치·날짜·크기 메타데이터, 앨범 조회) | Core, SampleRecorder(Debug 전용) |
| 3 | Classifier(FoundationModels), Notification, (ImageAnalysis 확장: 바코드) | |
| 4 | Map(지도 앱 열기, 역지오코딩(여행 폴더 상세·미리 받기)), Pasteboard(이 기기만 복사), WidgetTimeline(위젯 갱신 요청), (PhotoStore 확장: 장소 캐시·여행 사진·기간 캡처 조회, 영수증 추출 값·목록 조회, 캡처 묶음 추출 값·목록 조회, 검색 목록 조회, 최근 스크린샷 보관·조회, 특징 벡터 저장·비슷한 사진 조회, App Group 저장 위치·옛 위치에서 옮기기·위젯용 읽기 전용 열기), (PhotoLibrary 확장: 삭제), (ImageAnalysis 확장: 특징 벡터), (Indexing 확장: 특징 벡터 1단계·소급) | DesignSystem, Library 확장(카테고리 화면, 기프티콘 목록·캡처 행동, 여행 폴더, 영수증 목록, 쇼핑·대화·지도 묶기, 검색, 정리 도우미(기프티콘 정리·최근 스크린샷·비슷한 사진)), ExpiryWidget(만료 임박 위젯), Extension `Widget`(위젯 조립 지점) |
| 5 | TripPlace(여행 장소 이름 미리 받기, Map·PhotoStore 조합), BackgroundIndexing(앱이 뒤에 있거나 닫혀 있을 때의 분류: 뒤로 갈 때 멈춤·BG 처리 작업·사용자가 시작한 계속 처리 작업, Indexing·TripPlace·WidgetTimeline 조합), (PhotoLibrary 확장: restricted 상태), (Indexing 확장: 실행 하나·BG 실행), (TripPlace 확장: 저장소 출입 막기·회차 진행 알림), (ImageAnalysis 확장: 벡터 시한 차단 앞·뒤, 앞에서 불러 둔 분류·벡터 요청 재사용) | Onboarding 확장, Library 확장(앱이 뒤로 감·앞으로 옴 이벤트) |

## 작업 진행 방식
1. 로드맵의 주차 목표와 완료 기준을 확인 → 작업 단위로 쪼갠다.
2. `feat|fix|chore/<요약>` 브랜치 생성 (주차 표시 없이, CONVENTIONS §5).
3. Client 가 필요하면 **Interface 먼저** 설계(프로토콜 + 값 타입) → Fake → Feature Model + 테스트 → Impl 순서. Impl 없이도 Example 앱으로 화면을 확인할 수 있다.
4. 역할 단위로 작업 범위·수용 확인을 정하고 구현 → `/verify` → `/arch-review`. 새 상태·실패 경로가 생기는 구현과 그런 수정이 필요한 리뷰 지적은 팀으로 한다 (CONVENTIONS §6 "팀 구현"). 커밋은 사용자 지시로 `/micro-commit` (CONVENTIONS §5).
5. 사용자 지시로 `/pr` (마지막 커밋 검사(빌드에 영향이 있으면 lint·빌드·테스트) + 전체 `/arch-review` → PR 생성, 유형 라벨) → CI + Claude 리뷰 → 리뷰 반영 커밋도 `/pr` 로 push (CI 지적에 답) → 머지 전 확인 뒤 Merge commit 으로 머지 (CONVENTIONS §5 "리뷰 지적 처리").
6. 결정이 바뀌었으면 문서 갱신을 같은 PR 에 포함한다 (별도 커밋, type 은 CONVENTIONS §5 마이크로 커밋 표).

## 완료 기준 (Definition of Done)
- [ ] `/pr` 의 마지막 커밋 검사 PASS·SKIP, 필수 체크 `ci-result` 통과, 머지 전 확인 충족 (CONVENTIONS §5 "리뷰 지적 처리")
- [ ] CONVENTIONS §3 이 요구하는 테스트 (미뤘으면 그 보류 기록, CONVENTIONS §5 "리뷰 지적 처리")
- [ ] 해당하는 수동 확인(Example 앱 주요 상태, 실기기) 완료 (CONVENTIONS §5 표 "수동 확인" 행)
- [ ] 개인정보 규칙 위반 없음 (네트워크, 민감 로그)

## 출시 전 준비 체크리스트 (코드 외)
| 항목 | 필요 시점 | 상태 |
|---|---|---|
| Apple Developer Program 가입 (개인, 연 99달러) | W1 실기기 테스트 전 | ☑ |
| App ID `com.zopandagom.snapsort`(+ 위젯 `com.zopandagom.snapsort.widget`) + App Group `group.com.zopandagom.snapsort` 등록 | W4 (위젯과 SwiftData 저장소 공유. App Group 은 등록함, App ID 연결은 첫 실기기 빌드 서명에서 확인한 뒤 ☑) | ☐ |
| App Store Connect 앱 생성, 앱 이름 선점 ("간직함" / 영어 "Ganjik") | 가능한 빨리 | ☐ |
| 분류 정확도용 샘플 세트 (카테고리별 20장+. 이미지는 커밋하지 않고 실기기에서 Debug 기록 도구로 기록한 분류 입력을 가려서 `ClassificationSamples.json` 에 넣는다, CONVENTIONS §3) | W2 시작 전 | ☐ |
| 가격 정책 결정: 무료(인앱 결제 없음), 2026-10-26 결정 | W5 전 | ☑ |
| `PrivacyInfo.xcprivacy` 작성, 개인정보 처리방침 페이지 (위치 좌표의 Apple 시스템 서비스 사용, 분류 결과 저장 파일의 기기 백업 제외 명시) | W6 | ☐ |
| 사진 권한 문구(`NSPhotoLibraryUsageDescription`)를 전체 이미지 분류·정리(삭제) 용도로 수정 | 전체 이미지 조회 PR | ☑ |
| 스토어 스크린샷·설명·키워드 (ASO) | W6 | ☐ |

## 위험과 대응
| 위험 | 대응 |
|---|---|
| Foundation Models 미지원 기기 비율이 높음 | 규칙 기반 분류만으로도 쓸 만한 품질을 W2 에서 확보. AI 는 정확도 향상 요소로 취급 |
| 한국 기프티콘 형식이 다양 (카카오, 네이버, 편의점 등) | 만료일·교환처 추출을 Core 순수 함수(`GifticonExtractor`)로 두고 발급처별 형식을 지어낸 OCR 줄로 테스트(정확도 픽스처는 OCR 줄이 가려져 있다, CONVENTIONS §3). 실기기 정확도는 추출 값을 저장한 뒤 확인 |
| 대용량 보관함(수만 장)에서 분석 시간 | 식별자만 먼저 조회, 증분 분석, 진행률 표시. 썸네일로 분석하고 OCR 은 필요한 이미지에만. Debug 기록 도구의 속도 모드로 1만 장 기준 측정 |
| 백그라운드 분류(`BGProcessingTask`·계속 처리 작업 `BGContinuedProcessingTask`)가 시뮬레이터에서 돌지 않고(계속 처리 제출은 실측 code 1 `unavailable`), 언제 도는지·진행이 멈춘 듯하면 언제 끝내는지 시스템이 정함. 뒤에서 분류 모델을 새로 불러오지 못할 때가 있음(실기기 iPhone 14 Pro: `Missing weights`, CPU 고정은 늘·기본 장치는 때때로 실패해 Vision 연속 실패로 멈춤) | 스케줄러·작업·앱 상태 대역으로 순서를 테스트하고(계속 처리 작업은 진행 표시를 기록하는 작업 대역으로 진행률·문구·끝·겹침까지), 계속 처리 작업은 장소 구간에도 회차의 키 단위 진행을 보내 진행이 멈추지 않게 하며, 뒤 Vision 은 앞에서 불러 둔 분류·벡터 요청을 재사용하고(뒤에서 새로 불러오지 않고, 없으면 남은 분류를 앞으로 미룸, ARCHITECTURE §4 인덱싱 분류 요청 재사용), 실기기에서 확인한다: 계속 처리 + 재사용(새로 설치 → 온보딩 시작 → 분류가 수십 장 진행된 뒤 홈. 홈 전에 `vision session ready kind=classify active=1`(벡터 대상이 있었으면 `kind=featurePrint` 도), 뒤에서 잠금 화면 개수가 오르고 `indexing hold ended classified=<늘어남> … visionFailures=0 … classificationHeld=0 active=0`(벡터 대상이 있었으면 `featurePrints>0`)·`continued end reached=1`, `vision session discarded` 없음. 가능하면 수백 장·수 분 이상 뒤에서 돌게 두고 `seconds=`·`maxGap=` 기록), 온보딩 시작 직후 1~2초 안에 홈(`vision session ready` 가 없으면 `classificationHeld>0`·크래시 없음·앱을 열면 분류가 이어짐), 같은 프로세스의 처리 작업(앱에서 분류가 돈 뒤 홈 → lldb 강제 실행 → `start active=0` → `indexing hold ended classified>0 … classificationHeld=0 visionFailures=0`. 분류가 도는 도중 계속 처리 없이 홈으로 나가 몇 분 정지시킨 뒤 강제 실행했을 때도 `vision work timed out` 뒤 `classificationHeld>0` 이 아닌지 — 정지 중 흐른 시한의 거짓 초과, ARCHITECTURE §4 인덱싱 한계), 세션 없는 뒤(분류할 사진이 없는 채로 새로 실행해 `vision session ready kind=classify` 가 없음 → 홈 → 스크린샷 몇 장 → lldb 강제 실행 → `indexing hold ended classified=0 … classificationHeld=<새 장 수> visionFailures=0`·`end remaining=0`(다른 미룸이 없을 때) → 앱을 열면 그 스크린샷이 분류되고, 진행 카드에 "읽지 못한 n장…" 이 잠깐 보이는지), 세션 메모리(Xcode Debug navigator 값을 분류 시작 전·`vision session ready` 뒤·분류 끝난 뒤), 세션 버림이 보이면 `vision failed kind= code= visionError=` 와 함께 기록, `vision work timed out` 이 없는지(있으면 `callerWaiting=`·`firstUse=`·`active=` 와 함께 기록), Debug 기록 도구로 앞 `classifyMs` 첫 장(모델 적재)·중앙값·최대를 기록해 시한(5초, 첫 작업 20초)과 비교, 계속 처리 작업은 새로 설치 → 온보딩 시작 → 분류 중 홈에서 잠금 화면·다이내믹 아일랜드의 "이미지 분류 중 n/m장"과 오르는 개수(Debug `register … continued=1` 먼저), 시스템 진행 화면 취소 뒤 크래시 없음·다시 열면 이어 감(`continued end … expired=1`·처리 작업 제출), 끝나면 표시가 사라지는 모양, 진행 카드 "홈으로 나가도 계속" 버튼 → 홈 → 이어짐(버튼 숨김, 취소 뒤 복귀하면 다시 보임), 여행이 있는 보관함에서 글자 읽기 뒤 "장소 이름 받는 중 n/m곳"으로 바뀌고 강제 만료 없이 끝나는지(막대가 뒤로 가는 모양, `continued end … maxGap=`·`placeRounds=`·`tailSeconds=`), 장소 구간 취소 뒤 남은 이름이 채워지는지, 동기 제출이 바로 시작 못 할 때 code 4 를 던지는지(`continued submit ok` 뒤 `continued start` 없음), (선택) 앱 전환기에서 쓸어 닫을 때 작업이 계속되는지. 처리 작업은 lldb 로 강제 실행·만료 흉내(끈 앱을 BG 로 띄운 뒤 열면 개수·대표가 곧 보이고 멈춤 안내 없음), 밤새 충전 중 실제 실행, 분류 중 홈으로 나가기 반복(계속 처리 작업 있음·없음 각각)의 0xdead10cc, 잠긴 기기의 Vision·OCR·모델 거부(계속 처리 작업 중 포함, `indexing hold ended … active=0`), 재부팅 뒤 첫 잠금 해제 전 (ARCHITECTURE §4 인덱싱 확인 못 한 값) |
| iCloud 저장 공간 최적화로 원본이 기기에 없음 | 네트워크로 원본을 받지 않고(`isNetworkAccessAllowed = false`) 기기에 있는 버전만 쓴다. 분류·OCR 대상 판정용 바코드 확인은 썸네일, OCR·바코드 크게 보기는 기기에 있는 가장 큰 버전 |
| iOS 사진 앱의 검색·여행 추억과 기능이 겹침 | 차별점은 위 "사진 앱과의 차별 기능" 절에 둔다 |
| 차별 기능 추가로 출시 일정이 빠듯함 | 주마다 진행 상황을 점검하고, 늦어지면 출시 후로 미룰 항목을 사용자와 다시 정한다 |
| CI macOS 분 소진 (비공개 무료 플랜 2,000분, macOS 10배) | 문서만 바뀐 PR 은 CI 생략, lint 는 Ubuntu. 부족하면 셀프 호스트 러너나 레포 공개 검토 |
