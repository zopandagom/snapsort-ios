/// 보관함 홈 "곧 만료" 띠의 칩 하나 (docs/ARCHITECTURE.md §4 카테고리 화면).
/// 추출 값에 사진에서 읽은 텍스트가 들어 있으므로 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
public struct ExpiringGifticon: Sendable, Hashable, Identifiable {
  /// 상세에 그대로 싣는다(`PhotoPage.gifticon`).
  public let item: GifticonListItem
  public let expiryDate: LocalDate
  /// 늘 `.remaining(days:)` 이고 일수는 0...`ExpiryWidgetTimeline.windowDays`.
  public let due: GifticonDue

  public var id: ImageAsset.ID { self.item.id }

  public init(item: GifticonListItem, expiryDate: LocalDate, due: GifticonDue) {
    self.item = item
    self.expiryDate = expiryDate
    self.due = due
  }
}

/// 보관함 홈 "곧 만료" 띠 전체 (docs/ARCHITECTURE.md §4 카테고리 화면).
/// 같은 저장소 상태로 만든 위젯 오늘 요약(`ExpiryWidgetTimeline.summaries(...)[0].count`)과 `count` 가 같다:
/// 같은 창 판정(`ExpiryWidgetTimeline.isInWindow`)·같은 제외 조건(사용함·추출 대기·만료일 모름)을 쓴다.
public struct ExpiringGifticons: Sendable, Hashable {
  /// 이 값을 계산한 날(기기 시간대의 오늘).
  public let today: LocalDate
  /// 창 안 전체 개수(띠 머리의 n). 상한 때문에 `items.count` 보다 클 수 있다.
  public let count: Int
  /// 앞 `limit` 개. 순서는 기프티콘 목록 만료 임박순의 "남은 것" 섹션과 같다(만료일 오름차순, 같은 날이면 최신순).
  public let items: [ExpiringGifticon]

  public var isEmpty: Bool { self.count < 1 }

  public init(today: LocalDate, count: Int, items: [ExpiringGifticon]) {
    self.today = today
    self.count = count
    self.items = items
  }

  /// 미사용 ∧ 추출됨 ∧ 만료일이 `ExpiryWidgetTimeline.isInWindow(_:on: today)` 인 기프티콘.
  /// 추출 대기(`.checking`)·만료일 모름·사용함·어제 이전·`today + windowDays` 뒤는 빠진다.
  /// 정렬은 `GifticonExpirySection.sections(of:today:)` 의 남은 것 섹션을 그대로 쓴다(규칙을 다시 쓰지 않는다).
  /// - Parameters:
  ///   - items: 저장소 `gifticons()` 결과 전체(오늘로 거르지 않은 것).
  ///   - today: 기기 시간대의 오늘(`LocalDate(now, calendar:)`).
  ///   - limit: `items` 에 담을 최대 개수(썸네일 상한). `count` 는 상한과 상관없이 센다.
  public static func make(from items: [GifticonListItem], today: LocalDate, limit: Int) -> ExpiringGifticons {
    let remaining = GifticonExpirySection.sections(of: items.filter { !$0.isUsed }, today: today)
      .first { $0.kind == .remaining }?.items ?? []
    let inWindow: [ExpiringGifticon] = remaining.compactMap { item in
      guard case let .extracted(info) = item.status, let expiryDate = info.expiryDate,
            ExpiryWidgetTimeline.isInWindow(expiryDate, on: today)
      else { return nil }
      let due = GifticonDue(expiryDate: expiryDate, today: today)
      return ExpiringGifticon(item: item, expiryDate: expiryDate, due: due)
    }
    return ExpiringGifticons(today: today, count: inWindow.count, items: Array(inWindow.prefix(max(limit, 0))))
  }
}
