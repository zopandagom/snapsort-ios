/// 기프티콘 목록의 만료 임박순 섹션 하나 (docs/ARCHITECTURE.md §4 카테고리 화면). 섹션 머리 문구는 화면이 정한다.
public struct GifticonExpirySection: Sendable, Hashable, Identifiable {
  public enum Kind: Sendable, Hashable {
    /// 만료일이 오늘이거나 뒤다(오늘 만료도 쓸 수 있다).
    case remaining
    /// 만료일이 오늘보다 앞이다.
    case expired
    /// 추출했는데 만료일을 찾지 못했다.
    case unknownExpiry
    /// 아직 추출하지 않았다(`GifticonListItem.Status.checking`).
    case checking
  }

  public let kind: Kind
  /// 비어 있지 않다.
  public let items: [GifticonListItem]

  public var id: Kind { self.kind }

  /// 만료 임박순. 섹션 순서: 남은 것 → 만료됨 → 만료일 모름 → 확인 중. 빈 섹션은 뺀다.
  /// 남은 것: 만료일 ≥ today, 만료일 오름차순. 만료됨: 만료일 < today, 만료일 내림차순(최근 만료부터).
  /// 같은 만료일(또는 만료일 없는 섹션) 안에서는 최신순(생성일 없는 것은 뒤, 같으면 식별자 순 — `ImageMonthSection` 과 같은 규칙).
  /// 경계는 `GifticonDue` 와 같다(`today.days(until:)` 가 0 이상이면 남은 것).
  public static func sections(of items: [GifticonListItem], today: LocalDate) -> [GifticonExpirySection] {
    var remaining: [(LocalDate, GifticonListItem)] = []
    var expired: [(LocalDate, GifticonListItem)] = []
    var unknownExpiry: [GifticonListItem] = []
    var checking: [GifticonListItem] = []
    for item in items {
      switch item.status {
      case .checking:
        checking.append(item)
      case let .extracted(info):
        if let expiryDate = info.expiryDate {
          if today.days(until: expiryDate) >= 0 {
            remaining.append((expiryDate, item))
          } else {
            expired.append((expiryDate, item))
          }
        } else {
          unknownExpiry.append(item)
        }
      }
    }
    let newer: (GifticonListItem, GifticonListItem) -> Bool = { ImageMonthSection.isNewer($0.asset, than: $1.asset) }
    let sections: [(Kind, [GifticonListItem])] = [
      (.remaining, remaining.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : newer($0.1, $1.1) }.map(\.1)),
      (.expired, expired.sorted { $0.0 != $1.0 ? $0.0 > $1.0 : newer($0.1, $1.1) }.map(\.1)),
      (.unknownExpiry, unknownExpiry.sorted(by: newer)),
      (.checking, checking.sorted(by: newer)),
    ]
    return sections.filter { !$0.1.isEmpty }.map { GifticonExpirySection(kind: $0.0, items: $0.1) }
  }
}
