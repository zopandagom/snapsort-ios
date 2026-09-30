# 개발 계획

## 목표
- **제품:** 스크린샷을 기기 안에서 자동 분류하고, 기프티콘 만료일을 찾아 알려주는 앱.
- **시장 목표:** 한국 App Store 유료 차트 또는 카테고리(생산성·유틸리티) 1위.
- **출시 목표:** 2026-11-11 (6주, 풀타임).

## 로드맵
| 주차 | 기간 | 이슈 | 목표 | 완료 기준 |
|---|---|---|---|---|
| 0 | 9/30 | — | 모듈러 아키텍처, CI, 하네스, 문서 | 이 문서 세트 머지, CI 통과 |
| 1 | 10/1 – 10/7 | #1 | 사진 권한 온보딩 + 스크린샷 조회 | 전체/제한/거부 흐름, 신규 스크린샷 감지, Onboarding Feature |
| 2 | 10/8 – 10/14 | #2 | OCR + 규칙 기반 분류, SwiftData 저장 | OCR·Storage Client, Core 모듈, 픽스처 정확도 테스트 |
| 3 | 10/15 – 10/21 | #3 | Foundation Models 분류 + 기프티콘 추출, 만료 알림 | Classifier·Notification Client, 미지원 기기 폴백 |
| 4 | 10/22 – 10/28 | #4 | 메인 UI, 검색, 일괄 삭제, 위젯 | DesignSystem, 위젯 익스텐션(App Group) |
| 5 | 10/29 – 11/4 | #5 | StoreKit 2 결제, 온보딩 마감, TestFlight | 결제 Client, 외부 테스터 배포 |
| 6 | 11/5 – 11/11 | #6 | ASO, 스토어 에셋, 출시 | 심사 제출 |

### 주차별 예상 모듈
| 주차 | 새 Client | 새 Feature / Shared |
|---|---|---|
| 1 | (PhotoLibrary 확장: 변경 감지, 제한 접근 선택) | Onboarding |
| 2 | OCR, ScreenshotStore(SwiftData) | Core |
| 3 | Classifier(FoundationModels), Notification | Gifticon |
| 4 | — | DesignSystem, Library 확장, Widget |
| 5 | Purchase(StoreKit) | Paywall |

## 이슈 진행 방식
1. `gh issue view N` 으로 체크리스트 확인 → 필요하면 작업 단위로 쪼갠다.
2. `feat/wN-<요약>` 브랜치 생성.
3. Client 가 필요하면 **Interface 먼저** 설계(프로토콜 + 값 타입) → Fake → Feature Model + 테스트 → Impl 순서. Impl 없이도 Example 앱으로 화면을 확인할 수 있다.
4. 역할 단위로 구현 → `/verify` → `/arch-review` → `/micro-commit` (CONVENTIONS §5).
5. `/verify` 통과 → PR (`Closes #N`) → CI + Claude 리뷰 → Rebase merge.
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
| 분류 정확도용 샘플 스크린샷 세트 (카테고리별 20장+, 직접 만든 것만) | W2 시작 전 | ☐ |
| 가격 정책 결정 (유료 일회성 vs 무료 + 인앱) | W5 전 | ☐ |
| `PrivacyInfo.xcprivacy` 작성, 개인정보 처리방침 페이지 | W5 | ☐ |
| App Store Connect API 키 (TestFlight 자동 업로드) | W5 | ☐ |
| 스토어 스크린샷·설명·키워드 (ASO) | W6 | ☐ |

## 위험과 대응
| 위험 | 대응 |
|---|---|
| Foundation Models 미지원 기기 비율이 높음 | 규칙 기반 분류만으로도 쓸 만한 품질을 W2 에서 확보. AI 는 정확도 향상 요소로 취급 |
| 한국 기프티콘 형식이 다양 (카카오, 네이버, 편의점 등) | W2 픽스처에 주요 발급처 포함, 만료일 정규식을 Impl 순수 함수로 두고 테스트 |
| 대용량 보관함(수만 장)에서 분석 시간 | 식별자만 먼저 조회, 증분 분석, 진행률 표시. W2 에서 1만 장 기준 측정 |
| CI macOS 분 소진 (비공개 무료 플랜 2,000분, macOS 10배) | 문서만 바뀐 PR 은 CI 생략, lint 는 Ubuntu. 부족하면 셀프 호스트 러너나 레포 공개 검토 |
