/// 카테고리 화면(쇼핑·대화·지도)이 읽는 이미지 한 장 (docs/ARCHITECTURE.md §4 카테고리 화면).
/// 섹션 계산(`CaptureGroupSections`)의 입력이고 저장소 Interface 가 돌려주는 값이라 Core 에 둔다. `ReceiptListItem` 과 같은 모양이다.
/// 추출 값은 닫힌 목록의 값이지만 사진에서 읽은 것에서 나왔으므로 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
public struct CaptureGroupItem: Sendable, Hashable, Identifiable {
  public enum Status: Sendable, Hashable {
    /// 추출 전(OCR 대기, 추출 대기). 묶기 화면의 "확인 중".
    case checking
    case extracted(CaptureGroups)
  }

  public let asset: ImageAsset
  public let status: Status

  public var id: ImageAsset.ID { self.asset.id }

  public init(asset: ImageAsset, status: Status) {
    self.asset = asset
    self.status = status
  }
}
