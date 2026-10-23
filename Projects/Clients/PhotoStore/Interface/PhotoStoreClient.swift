import Core
import Foundation

/// 분류 결과 저장소 (SwiftData). 사진과 OCR 텍스트는 기기 안에만 저장한다 (docs/ARCHITECTURE.md §4).
/// 구현은 PhotoStoreImpl, 테스트 대역은 PhotoStoreTesting 에 있다.
public protocol PhotoStoreClient: Sendable {
  /// 분석한 이미지를 저장한다. 같은 식별자가 이미 있으면 새 결과로 바꾼다(OCR 대기 → 읽음도 이것으로 바꾼다).
  /// 기프티콘 추출 값(필드별 출처 `GifticonInfo.modelFilledFields` 포함)과 보강 상태(`IndexedImage.gifticonModelFill`)도
  /// 새 결과로 바꾼다(추출 값이 nil 이면 지운다). 영수증 추출 값(`IndexedImage.receipt`)도 새 결과로 바꾼다(nil 이면 지운다).
  /// 캡처 묶음 값(`IndexedImage.captureGroups`)도 새 결과로 바꾼다(nil 이면 지운다).
  /// 사용 여부는 넘긴 값이 아니라 저장된 값을 둔다: 새 카테고리에 기프티콘이 있으면 유지, 없으면 지운다(새 행은 미사용).
  func save(_ images: [IndexedImage]) async throws(PhotoStoreError)

  /// 보관함에서 지워진 이미지의 결과를 지운다. 없는 식별자는 무시한다.
  func delete(ids: Set<ImageAsset.ID>) async throws(PhotoStoreError)

  /// 저장된 이미지 식별자. 증분 인덱싱이 보관함과 비교해 새로 분석할 이미지를 고르는 데 쓴다.
  func indexedIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID>

  /// OCR 을 기다리는(`.pending`) 이미지 식별자. 인덱서 2단계가 할 일을 고르고 진행률의 대기 수를 센다. 순서는 인덱서가 정한다.
  func pendingTextRecognitionIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID>

  /// 기프티콘으로 분류돼 글자를 읽었는데 지금 규칙 버전(`GifticonExtractor.rulesVersion`)으로 추출하지 않은 이미지 식별자.
  /// 인덱서가 OCR 없이 저장된 줄로 소급 추출할 대상을 고른다.
  func gifticonExtractionPendingIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID>

  /// 추출 값만 바꾼다. 기프티콘으로 분류돼 글자를 읽었고 아직 지금 규칙 버전으로 추출하지 않은 행
  /// (`gifticonExtractionPendingIDs` 와 같은 조건)만 바꾸고, 없는 식별자와 그 밖의 행은 무시한다.
  /// 규칙으로 다시 추출했으므로 보강 상태도 `GifticonModelFill.initial(for:)` 로 되돌린다(보강을 다시 한다).
  /// 출처는 넘긴 `GifticonInfo.modelFilledFields` 로 쓰고, 사용 여부는 그대로 둔다. 부르는 쪽이 식별자 수를 배치 크기로 묶는다.
  func saveGifticons(_ gifticons: [ImageAsset.ID: GifticonInfo]) async throws(PhotoStoreError)

  /// 기프티콘으로 분류돼 글자를 읽었고 지금 규칙 버전으로 추출했는데 언어 모델 보강을 마치지 않은
  /// (`GifticonModelFill.pending`·`.stale`·`.sourcesUnknown`) 이미지 식별자. 인덱서가 소급 보강할 대상을 고른다.
  /// 추출 대기(`gifticonExtractionPendingIDs`)와 겹치지 않는다.
  func gifticonModelFillPendingIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID>

  /// 보강 결과를 저장한다. 보강 대기(`gifticonModelFillPendingIDs` 와 같은 조건)인 행만 바꾸고 없는 식별자와 그 밖의 행은
  /// 무시해, 겹친 지난 실행이 마친 행을 덮거나 규칙으로 다시 추출해야 하는 행에 값이 붙지 않는다.
  /// 결과마다 쓰는 값은 `GifticonModelFillResult` 문서대로다(출처는 담긴 `modelFilledFields` 로). 사용 여부는 그대로 둔다.
  /// 부르는 쪽이 식별자 수를 배치 크기로 묶는다.
  func saveGifticonModelFills(_ results: [ImageAsset.ID: GifticonModelFillResult]) async throws(PhotoStoreError)

  /// 영수증으로 분류돼 글자를 읽었는데 지금 규칙 버전(`ReceiptExtractor.rulesVersion`)으로 추출하지 않은 이미지 식별자.
  /// 인덱서가 OCR 없이 저장된 줄로 소급 추출할 대상을 고른다.
  func receiptExtractionPendingIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID>

  /// 영수증 추출 값만 바꾼다. `receiptExtractionPendingIDs` 와 같은 조건인 행만 바꾸고 없는 식별자와 그 밖의 행은 무시해,
  /// 겹친 지난 실행이 새 값을 덮지 않는다. 기프티콘 추출 값·보강 상태·사용 여부는 건드리지 않는다.
  /// 부르는 쪽이 식별자 수를 배치 크기로 묶는다.
  func saveReceipts(_ receipts: [ImageAsset.ID: ReceiptInfo]) async throws(PhotoStoreError)

  /// 쇼핑·대화·지도 중 하나로 분류돼 글자를 읽었는데 지금 규칙 버전(`CaptureGroupExtractor.rulesVersion`)으로 묶음 값을 추출하지 않은
  /// 이미지 식별자. 인덱서가 OCR 없이 저장된 줄로 소급 추출할 대상을 고른다.
  func captureGroupExtractionPendingIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID>

  /// 묶음 값만 바꾼다. `captureGroupExtractionPendingIDs` 와 같은 조건인 행만 바꾸고 없는 식별자와 그 밖의 행은 무시해,
  /// 겹친 지난 실행이 새 값을 덮지 않는다. 넘긴 값은 그 행의 카테고리로 `restricted(to:)` 해 쓴다.
  /// 기프티콘·영수증 추출 값과 사용 여부는 건드리지 않는다. 부르는 쪽이 식별자 수를 배치 크기로 묶는다.
  func saveCaptureGroups(_ groups: [ImageAsset.ID: CaptureGroups]) async throws(PhotoStoreError)

  /// 식별자로 저장된 이미지를 읽는다. 없는 식별자는 빠지고 순서는 정하지 않는다. 인덱서 2단계가 한 배치의 라벨을 읽고
  /// 소급 추출이 저장된 줄을 읽는 데 쓰므로, 부르는 쪽이 식별자 수를 배치 크기로 묶는다.
  func images(ids: Set<ImageAsset.ID>) async throws(PhotoStoreError) -> [IndexedImage]

  /// 그 카테고리에 속한 이미지를 최신순(생성일 없는 이미지는 맨 뒤, 같으면 식별자 순)으로 돌려준다.
  /// 라벨·OCR 줄까지 읽는다. 목록 화면은 `assets(in:)` 을 쓴다.
  func images(in category: ImageCategory) async throws(PhotoStoreError) -> [IndexedImage]

  /// 그 카테고리에 속한 이미지의 메타데이터를 최신순(생성일 없는 이미지는 맨 뒤, 같으면 식별자 순)으로 돌려준다.
  /// 라벨·OCR 줄·추출 값을 읽지 않아 `images(in:)` 보다 가볍다. 카테고리 화면처럼 자주 다시 읽는 목록에서 쓴다.
  /// 여행은 이미지 카테고리가 아니므로 `.travel` 은 늘 비어 있다.
  func assets(in category: ImageCategory) async throws(PhotoStoreError) -> [ImageAsset]

  /// 지금 규칙 버전으로 추출해 만료일을 찾은 기프티콘 중 만료일이 `date` 와 같거나 늦은 것을 만료일 오름차순(같으면 식별자 순)으로 돌려준다.
  /// 저장된 yyyymmdd 정수로 조건·정렬한다. 추출 대기 행(다른 규칙 버전, 만료일 정수를 날짜로 해석하지 못함)은 빠지므로,
  /// 이 결과에 없다는 것이 만료일이 없다는 뜻은 아니다. 알림을 지우기 전에 `gifticonExtractionPendingIDs()` 를 함께 본다.
  /// 보강 대기 행도 지금 값으로 든다(보강 대기는 알림을 막지 않는다). `.pending` 행은 규칙 값이고,
  /// `.stale` 행에 남은 옛 모델 값은 인덱서가 소급 보강에서 모델을 쓸 수 있든 없든 규칙 값으로 되돌린다.
  /// `.sourcesUnknown` 행은 지금 보강 버전으로 마친 값이라 그대로 든다(출처만 정하지 않았다).
  /// 사용한 기프티콘(`setGifticonUsed`)은 뺀다(알림을 받지 않는다).
  func upcomingGifticonExpiries(from date: LocalDate) async throws(PhotoStoreError) -> [GifticonExpiry]

  /// 기프티콘 카테고리의 모든 이미지를 최신순(생성일 없으면 뒤, 같으면 식별자 순)으로 돌려준다. 기프티콘 목록 화면이 쓴다.
  /// 라벨·OCR 줄을 디코딩하지 않는다.
  /// status: 지금 규칙 버전 추출 값이 있으면 `.extracted`, OCR 대기·추출 대기면 `.checking`,
  /// OCR 대상이 아닌 기프티콘(글자를 읽지 않음)은 찾을 값이 없어 `.extracted(GifticonInfo(expiryDate: nil, redemptionPlace: nil))`.
  /// 보강 상태가 `.stale`·`.sourcesUnknown` 인 행은 값의 출처를 몰라 `valuesMayBeFromModel` 로 만든다(값이 있는 필드 전부 "추정").
  func gifticons() async throws(PhotoStoreError) -> [GifticonListItem]

  /// `gifticons()` 의 한 장. 기프티콘 카테고리가 아니거나 없으면 nil. 상세가 열린 동안 다시 읽는 데 쓴다.
  func gifticon(id: ImageAsset.ID) async throws(PhotoStoreError) -> GifticonListItem?

  /// 영수증 카테고리의 모든 이미지를 최신순(생성일 없으면 뒤, 같으면 식별자 순)으로 돌려준다. 영수증 목록 화면이 쓴다.
  /// 라벨·OCR 줄을 디코딩하지 않는다.
  /// status: 지금 규칙 버전 추출 값이 있으면 `.extracted`, OCR 대기·추출 대기면 `.checking`,
  /// OCR 대상이 아닌 영수증(글자를 읽지 않음)은 찾을 값이 없어 `.extracted(.empty)`.
  func receipts() async throws(PhotoStoreError) -> [ReceiptListItem]

  /// 그 카테고리(쇼핑·대화·지도)의 모든 이미지를 최신순(생성일 없으면 뒤, 같으면 식별자 순, `assets(in:)` 과 같은 순서)으로 돌려준다.
  /// 카테고리 화면의 묶기가 쓴다. 라벨·OCR 줄을 디코딩하지 않는다.
  /// status: 지금 규칙 버전 묶음 값이 있으면 `.extracted`, OCR 대기·추출 대기면 `.checking`,
  /// OCR 대상이 아닌 이미지(글자를 읽지 않음)는 찾을 값이 없어 `.extracted(.empty)`.
  /// 그 밖의 카테고리는 빈 배열이다(카테고리 화면은 세 카테고리에만 부른다).
  func captureGroupItems(in category: ImageCategory) async throws(PhotoStoreError) -> [CaptureGroupItem]

  /// 사용 여부를 쓴다. 기프티콘 카테고리 행만 바꾸고 true, 없거나 기프티콘이 아니면 아무것도 바꾸지 않고 false.
  /// 추출 값·보강 상태는 건드리지 않는다. 사용자가 상세에서 바꿀 때만 부른다.
  func setGifticonUsed(_ isUsed: Bool, id: ImageAsset.ID) async throws(PhotoStoreError) -> Bool

  /// 카테고리별 이미지 수. 이미지가 없는 카테고리는 빠진다.
  /// 여행은 이미지 카테고리가 아니라 `tripCount()` 로 센다.
  func categoryCounts() async throws(PhotoStoreError) -> [ImageCategory: Int]

  /// 여행 판정 결과로 저장된 여행 전체를 바꾼다. 판정은 보관함 전체를 다시 보므로 일부만 고치지 않는다.
  /// 같은 저장에서 새 여행의 중심점 키(`Trip.placeKey`) 어디에도 해당하지 않는 장소 캐시를 지운다.
  func replaceTrips(_ trips: [Trip]) async throws(PhotoStoreError)

  /// 저장된 여행을 시작 시각 순(같으면 끝 시각 순)으로 돌려준다.
  func trips() async throws(PhotoStoreError) -> [Trip]

  /// 저장된 여행 수. 여행마다 든 사진 식별자를 읽지 않고 센다 (화면의 여행 개수처럼 자주 세는 곳에서 쓴다).
  func tripCount() async throws(PhotoStoreError) -> Int

  /// 식별자로 메타데이터만 읽는다. 넘긴 순서대로(중복은 처음 것만), 없는 식별자는 빠진다. 라벨·OCR 줄을 읽지 않는다.
  /// 여행 사진처럼 수천 개일 수 있어 Impl 이 1,000개씩 나눠 조회한다.
  func assets(ids: [ImageAsset.ID]) async throws(PhotoStoreError) -> [ImageAsset]

  /// 생성일이 interval.start 이상 interval.end 미만(끝 제외)이고 categories 중 하나에 속한 이미지의 메타데이터.
  /// 카테고리별 최신순(`assets(in:)` 과 같은 순서). 한 이미지가 여러 카테고리면 각각에 든다.
  /// 빈 카테고리·`.travel`·생성일 없는 이미지는 빠진다. 여행 폴더 상세가 그 기간의 캡처를 고르는 데 쓴다.
  func assets(
    in categories: Set<ImageCategory>,
    createdIn interval: DateInterval
  ) async throws(PhotoStoreError) -> [ImageCategory: [ImageAsset]]

  /// keys 중 장소 캐시가 있는 것. 이름은 그 locale 로 캐시된 것만 담고(다르면 nil), 시간대는 locale 과 무관하게 담는다.
  /// 캐시가 없는 키는 결과에 없다.
  func places(
    for keys: Set<RoundedCoordinate>,
    localeIdentifier: String
  ) async throws(PhotoStoreError) -> [RoundedCoordinate: CachedPlace]

  /// 장소 캐시에 쓴다. 같은 키는 locale·이름·시간대를 모두 덮는다. 저장된 여행 중 중심점 키가 key 인 여행이 없으면
  /// 쓰지 않고 false (지오코딩 도중 사진을 지워 여행이 사라졌을 때 캐시가 남지 않게).
  /// 요청 실패와 항목 없음(`placemarkNotFound`)은 부르는 쪽이 쓰지 않는다(다음에 다시 묻는다).
  func savePlace(
    _ name: CachedPlaceName,
    timeZoneIdentifier: String?,
    for key: RoundedCoordinate,
    localeIdentifier: String
  ) async throws(PhotoStoreError) -> Bool
}
