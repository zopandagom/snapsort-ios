import Foundation

/// 기프티콘 목록의 정렬 (docs/ARCHITECTURE.md §4 카테고리 화면). 선택은 저장하지 않는다(화면 일시 상태).
public enum GifticonSort: Sendable, Hashable, CaseIterable {
  /// 만료 임박순(`GifticonExpirySection`).
  case expiry
  /// 생성일 월별(`ImageMonthSection` 과 같은 묶음).
  case month
}

/// 기프티콘 목록의 월별 섹션 하나. 문구("날짜 없음")와 날짜 표시 형식은 화면이 정한다.
public struct GifticonMonthSection: Sendable, Hashable, Identifiable {
  /// nil 이면 생성일이 없는 섹션. 늘 맨 뒤에 하나만 있다.
  public let month: ImageMonth?
  /// 최신순(생성일 없는 것은 뒤, 같으면 식별자 순). 비어 있지 않다.
  public let items: [GifticonListItem]

  public var id: ImageMonth? { self.month }
}

/// 기프티콘 목록 화면이 그릴 섹션 전체. 화면이 저장소에서 읽은 목록·오늘·달력과 탭·정렬 선택으로 부르는 순수 함수다.
public enum GifticonListSections: Sendable, Hashable {
  case byExpiry([GifticonExpirySection])
  case byMonth([GifticonMonthSection])

  /// `used` 와 `isUsed` 가 같은 항목만 골라, 임박순이면 `GifticonExpirySection.sections`, 월별이면
  /// `ImageMonthSection.sections(of: assets, calendar:)` 로 나눈 뒤 식별자로 항목을 다시 붙인다.
  /// - Parameters:
  ///   - today: 만료 판정 기준. 기기 시간대의 오늘.
  ///   - calendar: 월 경계를 나누는 기기 달력·시간대.
  public static func sections(
    of items: [GifticonListItem],
    used: Bool,
    sort: GifticonSort,
    today: LocalDate,
    calendar: Calendar
  ) -> GifticonListSections {
    let selected = items.filter { $0.isUsed == used }
    switch sort {
    case .expiry:
      return .byExpiry(GifticonExpirySection.sections(of: selected, today: today))
    case .month:
      let byID = Dictionary(selected.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      return .byMonth(
        ImageMonthSection.sections(of: selected.map(\.asset), calendar: calendar).map { section in
          GifticonMonthSection(month: section.month, items: section.assets.compactMap { byID[$0.id] })
        }
      )
    }
  }
}
