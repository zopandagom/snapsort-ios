/// 영수증 목록이 읽는 영수증 한 장 (docs/ARCHITECTURE.md §4 카테고리 화면).
/// 섹션·합계 계산(`ReceiptListSections`)의 입력이고 저장소 Interface 가 돌려주는 값이라 Core 에 둔다.
/// 추출 값에 사진에서 읽은 텍스트(가게·금액)가 들어 있으므로 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
public struct ReceiptListItem: Sendable, Hashable, Identifiable {
  public enum Status: Sendable, Hashable {
    /// 추출 전(OCR 대기, 추출 대기). 목록의 "확인 중".
    case checking
    case extracted(ReceiptInfo)
  }

  public let asset: ImageAsset
  public let status: Status

  public var id: ImageAsset.ID { self.asset.id }

  public init(asset: ImageAsset, status: Status) {
    self.asset = asset
    self.status = status
  }
}
