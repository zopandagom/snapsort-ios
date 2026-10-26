/// 정리 화면 후보 한 장 (docs/ARCHITECTURE.md §4 정리 도우미).
public struct CleanupCandidate: Sendable, Hashable, Identifiable {
  public let item: GifticonListItem
  /// 방문의 첫 읽기에서 기본으로 고를지. 만료됨 섹션에서 만료일이 모델 추정이면 false.
  public let isSelectedByDefault: Bool

  public var id: ImageAsset.ID { self.item.id }
  public var asset: ImageAsset { self.item.asset }

  public init(item: GifticonListItem, isSelectedByDefault: Bool) {
    self.item = item
    self.isSelectedByDefault = isSelectedByDefault
  }
}

public struct CleanupSection: Sendable, Hashable, Identifiable {
  /// 섹션 종류. 지난 탑승권·예약·송장(후속 작업)은 여기에 case 를 더한다.
  public enum Kind: Sendable, Hashable, CaseIterable {
    case expiredGifticons
    case usedGifticons
  }

  public let kind: Kind
  /// 비어 있지 않다.
  public let candidates: [CleanupCandidate]

  public var id: Kind { self.kind }

  public init(kind: Kind, candidates: [CleanupCandidate]) {
    self.kind = kind
    self.candidates = candidates
  }
}

public struct CleanupSections: Sendable, Hashable {
  /// 화면 순서(만료됨 → 사용함). 빈 섹션은 뺀다.
  public let sections: [CleanupSection]
  /// 후보에서 뺀 미사용 확인 중(추출 대기·OCR 대기) 기프티콘 수. 화면 안내용.
  public let checkingGifticonCount: Int

  public var candidateIDs: Set<ImageAsset.ID> {
    Set(self.sections.flatMap { $0.candidates.map(\.id) })
  }

  public var isEmpty: Bool { self.sections.isEmpty }

  public init(sections: [CleanupSection], checkingGifticonCount: Int) {
    self.sections = sections
    self.checkingGifticonCount = checkingGifticonCount
  }

  /// 규칙:
  /// - 사용함(`isUsed`): 상태와 관계없이 "사용함" 섹션, 기본 선택. 최신순(`ImageMonthSection.isNewer`).
  /// - 미사용 `.checking`: 후보 아님, `checkingGifticonCount` 에 센다.
  /// - 미사용 `.extracted` 이고 만료일이 있고 `today.days(until: expiry) < 0`: "만료됨" 섹션.
  ///   기본 선택 = `!item.estimatedFields.contains(.expiryDate)`. 순서는 `GifticonExpirySection` 의 만료됨과 같다(최근 만료부터, 같으면 최신순).
  /// - 그 밖(만료일 없음, 오늘 이후 만료, 오늘 만료): 후보 아님.
  /// 한 장은 한 섹션에만 든다(사용함이 먼저).
  public static func gifticons(_ items: [GifticonListItem], today: LocalDate) -> CleanupSections {
    var expired: [(LocalDate, GifticonListItem)] = []
    var used: [GifticonListItem] = []
    var checkingCount = 0
    for item in items {
      if item.isUsed {
        used.append(item)
        continue
      }
      switch item.status {
      case .checking:
        checkingCount += 1
      case let .extracted(info):
        if let expiryDate = info.expiryDate, today.days(until: expiryDate) < 0 {
          expired.append((expiryDate, item))
        }
      }
    }
    let newer: (GifticonListItem, GifticonListItem) -> Bool = { ImageMonthSection.isNewer($0.asset, than: $1.asset) }
    let expiredCandidates = expired
      .sorted { $0.0 != $1.0 ? $0.0 > $1.0 : newer($0.1, $1.1) }
      .map { CleanupCandidate(item: $0.1, isSelectedByDefault: !$0.1.estimatedFields.contains(.expiryDate)) }
    let usedCandidates = used.sorted(by: newer).map { CleanupCandidate(item: $0, isSelectedByDefault: true) }
    let sections: [CleanupSection] = [
      CleanupSection(kind: .expiredGifticons, candidates: expiredCandidates),
      CleanupSection(kind: .usedGifticons, candidates: usedCandidates),
    ]
    return CleanupSections(sections: sections.filter { !$0.candidates.isEmpty }, checkingGifticonCount: checkingCount)
  }
}
