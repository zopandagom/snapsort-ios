# 개발 계획

## 목표
- **제품:** 사진 보관함의 이미지를 기기 안에서 자동 분류하고(정보형·사진형 카테고리), 기프티콘 만료일을 찾아 알려주는 앱.
- **시장 목표:** 한국 App Store 유료 차트 또는 카테고리(생산성·유틸리티) 1위.
- **출시 목표:** 2026-11-11 (6주, 풀타임).

## 사진 앱과의 차별 기능 (MVP)
iOS 사진 앱도 기기 안에서 "여행", "음식" 검색과 여행 추억을 제공한다. 그래서 차별점은 사진 앱이 하지 않는 **카테고리별 묶음, 정리, 카테고리를 가로지르는 연결, 캡처에서 바로 행동**에 둔다.

| 영역 | 기능 | 기술 메모 |
|---|---|---|
| 카테고리별 묶음 | 모든 카테고리는 월별 섹션이 기본. 추가 기준: 기프티콘 만료 임박순·사용함/미사용, 영수증 가게별 + 월 합계 금액, 여행 여행 단위 폴더, 쇼핑 브랜드·쇼핑몰별, 대화 캡처 앱별, 지도 지역별·지도 위 핀 | 카테고리마다 "무엇으로 묶을지"를 갖도록 저장 모델을 설계 (SwiftData 모델 설계 전에 확정) |
| 카테고리 연결 | 여행 폴더에 그 기간의 캡처(항공권·숙소 예약·영수증·지도 캡처)를 함께 모은다 | 여행 판정(위치·날짜) 결과의 기간으로 다른 카테고리 이미지를 묶음 |
| 정리 도우미 | 지난 것 정리 추천(만료된 기프티콘, 지난 탑승권·예약, 배송 끝난 송장), 비슷한 이미지 묶기, "N장 정리하면 X GB 확보" + 일괄 삭제, 캡처 인박스(새 캡처를 한 장씩 보관/삭제) | 비슷한 이미지는 Vision 특징 벡터(`GenerateImageFeaturePrintRequest`) 거리. 삭제는 `PHAssetChangeRequest.deleteAssets`. 확보 용량은 추정치로 표시하고, 지운 사진은 '최근 삭제된 항목'에 30일 남으므로 비우면 확보된다고 안내 (계산 방법은 구현 때 측정해 확정). 제한 접근이면 고른 사진 안에서만 정리하고 화면에 안내 |
| 캡처를 행동으로 | 기프티콘 바코드 크게 보기(화면 밝기 최대), 주소 → 지도 앱 열기, 송장·계좌번호 복사 | 바코드는 Vision `DetectBarcodesRequest` 로 읽어 다시 그림. 주소·번호는 OCR 텍스트에서 추출 |

### 출시 후 후보
- 일정 캡처 → 캘린더에 추가 (EventKit)

## 로드맵
| 주차 | 기간 | 목표 | 완료 기준 |
|---|---|---|---|
| 0 | 9/30 | 모듈러 아키텍처, CI, 하네스, 문서 | 이 문서 세트 머지, CI 통과 |
| 1 | 10/1 – 10/7 | 사진 권한 온보딩 + 이미지 조회 | 전체/제한/거부 흐름, 신규 이미지 감지, Onboarding Feature |
| 2 | 10/8 – 10/14 | Vision 이미지 분류 + OCR + 규칙 기반 분류, 여행 판정, SwiftData 저장 | ImageAnalysis·PhotoStore Client, Core 모듈, 픽스처 정확도 테스트 |
| 3 | 10/15 – 10/21 | Foundation Models 분류 + 기프티콘 추출, 만료 알림, 캡처 정보 추출(바코드·주소·송장·계좌) | Classifier·Notification Client, 미지원 기기 폴백 |
| 4 | 10/22 – 10/28 | 메인 UI(카테고리별 묶음, 여행 폴더), 검색, 정리 도우미, 위젯 | DesignSystem, 위젯 익스텐션(App Group) |
| 5 | 10/29 – 11/4 | StoreKit 2 결제, 온보딩 마감, TestFlight | 결제 Client, 외부 테스터 배포 |
| 6 | 11/5 – 11/11 | ASO, 스토어 에셋, 출시 | 심사 제출 |

### 주차별 예상 모듈
| 주차 | 새 Client | 새 Feature / Shared |
|---|---|---|
| 1 | (PhotoLibrary 확장: 변경 감지, 제한 접근 선택) | Onboarding |
| 2 | ImageAnalysis(Vision 이미지 분류·OCR), PhotoStore(SwiftData), (PhotoLibrary 확장: 위치·날짜·크기 메타데이터) | Core |
| 3 | Classifier(FoundationModels), Notification, (ImageAnalysis 확장: 바코드) | Gifticon |
| 4 | 지오코딩·지도 앱 열기 Client (이름은 구현 PR 에서 확정), (PhotoLibrary 확장: 삭제), (ImageAnalysis 확장: 특징 벡터) | DesignSystem, Library 확장, Widget |
| 5 | Purchase(StoreKit) | Paywall |

## 작업 진행 방식
1. 로드맵의 주차 목표와 완료 기준을 확인 → 작업 단위로 쪼갠다.
2. `feat|fix|chore/<요약>` 브랜치 생성 (주차 표시 없이, CONVENTIONS §5).
3. Client 가 필요하면 **Interface 먼저** 설계(프로토콜 + 값 타입) → Fake → Feature Model + 테스트 → Impl 순서. Impl 없이도 Example 앱으로 화면을 확인할 수 있다.
4. 역할 단위로 구현 → `/verify` → `/arch-review`. 커밋은 사용자 지시로 `/micro-commit` (CONVENTIONS §5).
5. 사용자 지시로 `/pr` (전체 `/arch-review` → PR 생성, 유형 라벨) → CI + Claude 리뷰 → Merge commit 으로 머지.
6. 결정이 바뀌었으면 docs 갱신을 같은 PR 에 포함 (별도 `docs:` 커밋).

## 완료 기준 (Definition of Done)
- [ ] `make lint`, `make test` 로컬 통과, CI 녹색
- [ ] 새 Model 이벤트와 Client 순수 로직에 테스트
- [ ] Example 앱에서 주요 상태(정상/빈 상태/권한 거부/오류) 확인
- [ ] 개인정보 규칙 위반 없음 (네트워크, 민감 로그)
- [ ] 실제 기기에서 한 번 이상 확인 (PhotoKit·Vision·Foundation Models 는 시뮬레이터와 동작이 다를 수 있음)

## 출시 전 준비 체크리스트 (코드 외)
| 항목 | 필요 시점 | 상태 |
|---|---|---|
| Apple Developer Program 가입 (개인, 연 99달러) | W1 실기기 테스트 전 | ☐ |
| App ID `com.zopandagom.snapsort` + App Group 등록 | W2 (SwiftData 공유 컨테이너) | ☐ |
| App Store Connect 앱 생성, 앱 이름 선점 ("SnapSort" / 한국어 이름) | 가능한 빨리 | ☐ |
| 분류 정확도용 샘플 이미지 세트 (카테고리별 20장+, 직접 찍거나 만든 것만) | W2 시작 전 | ☐ |
| 가격 정책 결정 (유료 일회성 vs 무료 + 인앱) | W5 전 | ☐ |
| `PrivacyInfo.xcprivacy` 작성, 개인정보 처리방침 페이지 (위치 좌표의 Apple 시스템 서비스 사용 명시) | W5 | ☐ |
| 사진 권한 문구(`NSPhotoLibraryUsageDescription`)를 전체 이미지 분류·정리(삭제) 용도로 수정 | 전체 이미지 조회 PR | ☑ |
| App Store Connect API 키 (TestFlight 자동 업로드) | W5 | ☐ |
| 스토어 스크린샷·설명·키워드 (ASO) | W6 | ☐ |

## 위험과 대응
| 위험 | 대응 |
|---|---|
| Foundation Models 미지원 기기 비율이 높음 | 규칙 기반 분류만으로도 쓸 만한 품질을 W2 에서 확보. AI 는 정확도 향상 요소로 취급 |
| 한국 기프티콘 형식이 다양 (카카오, 네이버, 편의점 등) | W2 픽스처에 주요 발급처 포함, 만료일 정규식을 Impl 순수 함수로 두고 테스트 |
| 대용량 보관함(수만 장)에서 분석 시간 | 식별자만 먼저 조회, 증분 분석, 진행률 표시. 썸네일로 분석하고 OCR 은 필요한 이미지에만. W2 에서 1만 장 기준 측정 |
| iCloud 저장 공간 최적화로 원본이 기기에 없음 | 네트워크로 원본을 받지 않고(`isNetworkAccessAllowed = false`) 기기에 있는 버전만 쓴다. 분류는 썸네일, OCR·바코드는 기기에 있는 가장 큰 버전 |
| iOS 사진 앱의 검색·여행 추억과 기능이 겹침 | 차별점은 위 "사진 앱과의 차별 기능" 절에 둔다 |
| 차별 기능 추가로 출시 일정이 빠듯함 | 주마다 진행 상황을 점검하고, 늦어지면 출시 후로 미룰 항목을 사용자와 다시 정한다 |
| CI macOS 분 소진 (비공개 무료 플랜 2,000분, macOS 10배) | 문서만 바뀐 PR 은 CI 생략, lint 는 Ubuntu. 부족하면 셀프 호스트 러너나 레포 공개 검토 |
