import Core

/// 분류 결과 저장소 (SwiftData). 사진과 OCR 텍스트는 기기 안에만 저장한다 (docs/ARCHITECTURE.md §4).
/// 구현은 PhotoStoreImpl, 테스트 대역은 PhotoStoreTesting 에 있다.
public protocol PhotoStoreClient: Sendable {
  /// 분석한 이미지를 저장한다. 같은 식별자가 이미 있으면 새 결과로 바꾼다.
  func save(_ images: [IndexedImage]) async throws(PhotoStoreError)

  /// 보관함에서 지워진 이미지의 결과를 지운다. 없는 식별자는 무시한다.
  func delete(ids: Set<ImageAsset.ID>) async throws(PhotoStoreError)

  /// 저장된 이미지 식별자. 증분 인덱싱이 보관함과 비교해 새로 분석할 이미지를 고르는 데 쓴다.
  func indexedIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID>

  /// 그 카테고리에 속한 이미지를 최신순(생성일 없는 이미지는 맨 뒤)으로 돌려준다.
  func images(in category: ImageCategory) async throws(PhotoStoreError) -> [IndexedImage]

  /// 카테고리별 이미지 수. 이미지가 없는 카테고리는 빠진다.
  /// 여행은 이미지 카테고리가 아니라 `trips()` 로 센다.
  func categoryCounts() async throws(PhotoStoreError) -> [ImageCategory: Int]

  /// 여행 판정 결과로 저장된 여행 전체를 바꾼다. 판정은 보관함 전체를 다시 보므로 일부만 고치지 않는다.
  func replaceTrips(_ trips: [Trip]) async throws(PhotoStoreError)

  /// 저장된 여행을 시작 시각 순(같으면 끝 시각 순)으로 돌려준다.
  func trips() async throws(PhotoStoreError) -> [Trip]
}
