import Foundation

/// 보관함 이미지 한 장의 메타데이터. 분류 파이프라인 ①단계 입력으로, 픽셀을 읽지 않고 얻는 값만 담는다 (docs/ARCHITECTURE.md §4).
/// PHAsset 은 Sendable 이 아니고 Interface 에 노출하지 않으므로 이 값 타입으로 넘긴다.
public struct ImageAsset: Sendable, Hashable, Identifiable {
  /// 보관함의 이미지 식별자 (PHAsset.localIdentifier).
  public let id: String
  /// 촬영·저장 시각. 보관함에 없으면 nil.
  public let creationDate: Date?
  /// 촬영 위치. 위치 정보가 없는 이미지(스크린샷, 저장 이미지 등)는 nil.
  public let coordinate: Coordinate?
  public let pixelWidth: Int
  public let pixelHeight: Int
  /// 기기에서 찍은 스크린샷인지. OCR 대상을 고르고 정보형·사진형을 가르는 분류 신호다.
  public let isScreenshot: Bool

  public init(
    id: String,
    creationDate: Date?,
    coordinate: Coordinate?,
    pixelWidth: Int,
    pixelHeight: Int,
    isScreenshot: Bool
  ) {
    self.id = id
    self.creationDate = creationDate
    self.coordinate = coordinate
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.isScreenshot = isScreenshot
  }
}
