/// 기프티콘 목록·상세가 읽는 기프티콘 한 장 (docs/ARCHITECTURE.md §4 카테고리 화면).
/// 섹션 계산(`GifticonListSections`)의 입력이고 저장소 Interface 가 돌려주는 값이라 Core 에 둔다.
/// 추출 값에 사진에서 읽은 텍스트가 들어 있으므로 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
public struct GifticonListItem: Sendable, Hashable, Identifiable {
  public enum Status: Sendable, Hashable {
    /// 추출 전(OCR 대기, 추출 대기). 목록의 "확인 중".
    case checking
    case extracted(GifticonInfo)
  }

  public let asset: ImageAsset
  public let status: Status
  public let isUsed: Bool
  /// 화면에 "추정"으로 보일 필드: 모델이 채운 필드, 그리고 값의 출처를 모르는 행(`valuesMayBeFromModel`)이면 값이 있는 필드 전부.
  /// `.checking` 이면 비어 있다.
  public let estimatedFields: Set<GifticonInfo.Field>
  /// `with(isUsed:)` 가 다시 만들 때 쓴다.
  private let valuesMayBeFromModel: Bool

  public var id: ImageAsset.ID { self.asset.id }

  /// - Parameter valuesMayBeFromModel: 값의 출처를 모르는 행(저장소 보강 상태가 다른 보강 버전이거나 출처를 아직 정하지 않은
  ///   옛 마침 행)이면 true. 옛 모델 값이 출처 없이 확인된 값처럼 보이지 않게 값이 있는 필드를 모두 "추정"으로 둔다.
  public init(asset: ImageAsset, status: Status, isUsed: Bool, valuesMayBeFromModel: Bool = false) {
    self.asset = asset
    self.status = status
    self.isUsed = isUsed
    self.valuesMayBeFromModel = valuesMayBeFromModel
    self.estimatedFields = switch status {
    case .checking:
      []
    case let .extracted(info) where valuesMayBeFromModel:
      Set(GifticonInfo.Field.allCases.filter { field in
        switch field {
        case .expiryDate: info.expiryDate != nil
        case .redemptionPlace: info.redemptionPlace != nil
        }
      })
    case let .extracted(info):
      info.modelFilledFields
    }
  }

  /// 사용 여부만 바꾼 값.
  public func with(isUsed: Bool) -> GifticonListItem {
    GifticonListItem(
      asset: self.asset,
      status: self.status,
      isUsed: isUsed,
      valuesMayBeFromModel: self.valuesMayBeFromModel
    )
  }
}
