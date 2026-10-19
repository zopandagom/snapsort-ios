/// 만료일을 찾은 기프티콘 한 장. 만료 알림 계획의 입력 (docs/ARCHITECTURE.md §4 만료 알림).
public struct GifticonExpiry: Sendable, Hashable {
  public let imageID: ImageAsset.ID
  public let expiryDate: LocalDate

  public init(imageID: ImageAsset.ID, expiryDate: LocalDate) {
    self.imageID = imageID
    self.expiryDate = expiryDate
  }
}
