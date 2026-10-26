import Core

/// `PhotoStoreClient.similarPhotoEntries()` 의 결과 (docs/ARCHITECTURE.md §4 정리 도우미). 사진에서 만든 벡터를 담으므로 로그에 남기지 않는다.
public struct SimilarPhotoEntries: Sendable, Equatable {
  /// 지금 버전 벡터가 있는 대상 사진 중 시간 이웃(`SimilarPhotoGrouping.linkableIDs`)이 있는 것. 생성일 오름차순(같으면 식별자 순).
  /// 시간 이웃이 없는 사진은 어떤 묶음에도 들 수 없어 뺀다(벡터를 읽는 양을 줄인다).
  public let photos: [FeaturePrintedPhoto]
  /// 대상인데 지금 버전 벡터가 없는 사진 수(`featurePrintPendingIDs` 와 같은 조건). 화면의 "아직 비교하지 않은 n장".
  public let uncomparedCount: Int

  public init(photos: [FeaturePrintedPhoto], uncomparedCount: Int) {
    self.photos = photos
    self.uncomparedCount = uncomparedCount
  }
}
