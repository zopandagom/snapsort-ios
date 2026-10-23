import Foundation

/// 영수증 목록의 묶음 (docs/ARCHITECTURE.md §4 카테고리 화면). 선택은 저장하지 않는다(화면 일시 상태).
public enum ReceiptGrouping: Sendable, Hashable, CaseIterable {
  /// 생성일 월별(`ImageMonthSection` 과 같은 묶음).
  case month
  /// 가게 묶음 키(`ReceiptInfo.storeKey`)별.
  case store
}

/// 한 통화의 합계.
public struct ReceiptCurrencyTotal: Sendable, Hashable {
  public let currency: ReceiptCurrency
  /// 최소 단위를 Decimal 로 더한 뒤 통화 자릿수로 나눈 정확한 값.
  public let amount: Decimal
  /// 합계에 든 영수증 수.
  public let count: Int

  public init(currency: ReceiptCurrency, amount: Decimal, count: Int) {
    self.currency = currency
    self.amount = amount
    self.count = count
  }
}

/// 섹션 하나의 합계. 통화를 섞어 더하지 않는다.
/// 취소 전표·금액 모름·확인 중은 합계에 넣지 않고, 금액 모름과 확인 중은 수만 센다(취소는 어느 수에도 넣지 않는다).
public struct ReceiptTotals: Sendable, Hashable {
  /// 통화별 합계. 든 영수증 수가 많은 통화부터, 같으면 `ReceiptCurrency.allCases` 순서. 빈 통화는 없다.
  public let currencies: [ReceiptCurrencyTotal]
  /// 추출했고 취소가 아닌데 금액이 nil 인 수.
  public let unknownAmountCount: Int
  /// `.checking` 수.
  public let checkingCount: Int

  public init(items: [ReceiptListItem]) {
    var sums: [ReceiptCurrency: (minorUnits: Decimal, count: Int)] = [:]
    var unknownAmountCount = 0
    var checkingCount = 0
    for item in items {
      switch item.status {
      case .checking:
        checkingCount += 1
      case let .extracted(info) where info.isCancelled:
        continue
      case let .extracted(info):
        guard let amount = info.amount else {
          unknownAmountCount += 1
          continue
        }
        // 최소 단위 정수를 Decimal 로 더해 Int 를 넘는 합도, 0.1 + 0.2 같은 소수 오차도 없다.
        let sum = sums[amount.currency, default: (0, 0)]
        sums[amount.currency] = (sum.minorUnits + Decimal(amount.minorUnits), sum.count + 1)
      }
    }
    self.currencies = ReceiptCurrency.allCases
      .compactMap { currency in
        sums[currency].map { sum in
          ReceiptCurrencyTotal(
            currency: currency,
            amount: sum.minorUnits * Decimal(sign: .plus, exponent: -currency.minorUnitDigits, significand: 1),
            count: sum.count
          )
        }
      }
      // 정렬이 안정적이라 같은 수면 allCases 순서가 남는다.
      .enumerated()
      .sorted { ($1.element.count, $0.offset) < ($0.element.count, $1.offset) }
      .map(\.element)
    self.unknownAmountCount = unknownAmountCount
    self.checkingCount = checkingCount
  }
}

/// 영수증 목록의 월별 섹션 하나. 문구("날짜 없음")와 날짜 표시 형식은 화면이 정한다.
public struct ReceiptMonthSection: Sendable, Hashable, Identifiable {
  /// nil 이면 생성일이 없는 섹션. 늘 맨 뒤에 하나만 있다.
  public let month: ImageMonth?
  /// 최신순(생성일 없는 것은 뒤, 같으면 식별자 순). 비어 있지 않다.
  public let items: [ReceiptListItem]
  public let totals: ReceiptTotals

  public var id: ImageMonth? { self.month }
}

/// 영수증 목록의 가게별 섹션 하나.
public struct ReceiptStoreSection: Sendable, Hashable, Identifiable {
  public enum Kind: Sendable, Hashable {
    /// 묶음 키가 같은 가게.
    case store(key: String)
    /// 추출했는데 가게를 못 찾았다(묶음 키 없음).
    case unknownStore
    /// 추출 전(확인 중).
    case checking
  }

  public let kind: Kind
  /// `.store` 면 섹션에서 가장 최근 영수증의 가게 이름. 그 밖은 nil.
  public let storeName: String?
  /// 최신순(생성일 없는 것은 뒤, 같으면 식별자 순). 비어 있지 않다.
  public let items: [ReceiptListItem]
  /// 그 가게의 전체 기간 합계.
  public let totals: ReceiptTotals

  public var id: Kind { self.kind }
}

/// 영수증 목록 화면이 그릴 섹션 전체. 화면이 저장소에서 읽은 목록·달력과 묶음 선택으로 부르는 순수 함수다.
public enum ReceiptListSections: Sendable, Hashable {
  case byMonth([ReceiptMonthSection])
  case byStore([ReceiptStoreSection])

  /// 월별이면 `ImageMonthSection.sections(of:calendar:)` 로 나눈 뒤 식별자로 항목을 다시 붙이고 섹션마다 합계를 낸다(날짜 없음 섹션 포함).
  /// 월 경계는 생성일마다 `calendar` 의 달력·시간대로 정한다.
  /// 가게별이면 추출한 항목을 묶음 키로 묶어 가장 최근 영수증이 있는 가게부터(생성일 없는 가게는 뒤, 같으면 식별자 순) 두고,
  /// 그 뒤에 가게 모름, 맨 끝에 확인 중 섹션을 둔다. 빈 섹션은 만들지 않는다.
  /// - Parameter calendar: 월 경계를 나누는 기기 달력·시간대. 가게별에서는 쓰지 않는다.
  public static func sections(
    of items: [ReceiptListItem],
    grouping: ReceiptGrouping,
    calendar: Calendar
  ) -> ReceiptListSections {
    let sorted = items.sorted { ImageMonthSection.isNewer($0.asset, than: $1.asset) }
    switch grouping {
    case .month:
      let byID = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      return .byMonth(
        ImageMonthSection.sections(of: sorted.map(\.asset), calendar: calendar).map { section in
          let sectionItems = section.assets.compactMap { byID[$0.id] }
          return ReceiptMonthSection(
            month: section.month,
            items: sectionItems,
            totals: ReceiptTotals(items: sectionItems)
          )
        }
      )
    case .store:
      return .byStore(self.storeSections(of: sorted))
    }
  }

  /// 섹션이 하나도 없는지(영수증이 없음).
  public var isEmpty: Bool {
    switch self {
    case let .byMonth(sections): sections.isEmpty
    case let .byStore(sections): sections.isEmpty
    }
  }

  /// `sorted` 는 최신순이다. 키별 항목도 그 순서를 지켜 첫 항목이 가장 최근 영수증이다.
  private static func storeSections(of sorted: [ReceiptListItem]) -> [ReceiptStoreSection] {
    var keyOrder: [String] = []
    var byKey: [String: [ReceiptListItem]] = [:]
    var unknownStore: [ReceiptListItem] = []
    var checking: [ReceiptListItem] = []
    for item in sorted {
      switch item.status {
      case .checking:
        checking.append(item)
      case let .extracted(info):
        guard let key = info.storeKey else {
          unknownStore.append(item)
          continue
        }
        if byKey[key] == nil {
          keyOrder.append(key)
        }
        byKey[key, default: []].append(item)
      }
    }
    // 최신순으로 처음 만난 키 순서가 곧 각 가게의 가장 최근 영수증 순서다.
    var sections = keyOrder.compactMap { key in
      byKey[key].map { items in
        let name: String? = if case let .extracted(info) = items.first?.status {
          info.storeName
        } else {
          nil
        }
        return ReceiptStoreSection(
          kind: .store(key: key),
          storeName: name,
          items: items,
          totals: ReceiptTotals(items: items)
        )
      }
    }
    for (kind, items) in [(ReceiptStoreSection.Kind.unknownStore, unknownStore), (.checking, checking)]
      where !items.isEmpty
    {
      sections.append(ReceiptStoreSection(
        kind: kind,
        storeName: nil,
        items: items,
        totals: ReceiptTotals(items: items)
      ))
    }
    return sections
  }
}
