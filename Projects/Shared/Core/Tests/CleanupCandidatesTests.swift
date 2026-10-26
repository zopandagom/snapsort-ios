import Core
import Testing

struct CleanupCandidatesTests {
  private static let today = gifticonDay(20_261_019)

  private static func sections(_ items: [GifticonListItem]) -> CleanupSections {
    CleanupSections.gifticons(items, today: self.today)
  }

  private static func estimated(_ id: String, expiry: Int, isUsed: Bool = false) -> GifticonListItem {
    GifticonListItem(
      asset: gifticonAsset(id),
      status: .extracted(GifticonInfo(
        expiryDate: gifticonDay(expiry),
        redemptionPlace: "가게",
        modelFilledFields: [.expiryDate]
      )),
      isUsed: isUsed
    )
  }

  @Test("어제 만료는 만료됨 섹션이고 기본 선택이다")
  func yesterdayIsExpiredAndSelected() throws {
    let result = Self.sections([extractedGifticon("a", expiry: 20_261_018)])

    let section = try #require(result.sections.first)
    #expect(section.kind == .expiredGifticons)
    #expect(section.candidates.map(\.id) == ["a"])
    #expect(section.candidates.first?.isSelectedByDefault == true)
  }

  @Test("오늘 만료와 내일 이후 만료, 만료일 없음은 후보가 아니다")
  func notExpiredIsNotCandidate() {
    let result = Self.sections([
      extractedGifticon("today", expiry: 20_261_019),
      extractedGifticon("tomorrow", expiry: 20_261_020),
      extractedGifticon("unknown", expiry: nil),
    ])

    #expect(result.isEmpty)
    #expect(result.candidateIDs.isEmpty)
    #expect(result.checkingGifticonCount == 0)
  }

  @Test("모델이 채운 만료일로 만료됐으면 후보지만 기본 선택이 아니다")
  func estimatedExpiryIsNotSelectedByDefault() {
    let result = Self.sections([Self.estimated("model", expiry: 20_261_001)])

    #expect(result.sections.first?.candidates.map(\.isSelectedByDefault) == [false])
  }

  @Test("교환처만 추정이면 기본 선택이다")
  func estimatedPlaceOnlyIsSelected() {
    let item = GifticonListItem(
      asset: gifticonAsset("place"),
      status: .extracted(GifticonInfo(
        expiryDate: gifticonDay(20_261_001),
        redemptionPlace: "가게",
        modelFilledFields: [.redemptionPlace]
      )),
      isUsed: false
    )

    #expect(Self.sections([item]).sections.first?.candidates.map(\.isSelectedByDefault) == [true])
  }

  @Test("출처를 모르는 행의 만료일은 추정이라 기본 선택이 아니다")
  func unknownSourceExpiryIsNotSelected() {
    let item = GifticonListItem(
      asset: gifticonAsset("old"),
      status: .extracted(GifticonInfo(expiryDate: gifticonDay(20_261_001), redemptionPlace: nil)),
      isUsed: false,
      valuesMayBeFromModel: true
    )

    #expect(Self.sections([item]).sections.first?.candidates.map(\.isSelectedByDefault) == [false])
  }

  @Test("미사용 확인 중은 후보가 아니고 수만 센다")
  func checkingIsCountedOnly() {
    let result = Self.sections([
      checkingGifticon("c1"),
      checkingGifticon("c2"),
      extractedGifticon("a", expiry: 20_261_001),
    ])

    #expect(result.candidateIDs == ["a"])
    #expect(result.checkingGifticonCount == 2)
  }

  @Test("사용함은 확인 중·미래 만료·만료 모두 사용함 섹션이고 기본 선택이며 확인 중 수에 세지 않는다")
  func usedAlwaysInUsedSection() {
    let result = Self.sections([
      checkingGifticon("checking", isUsed: true),
      extractedGifticon("future", expiry: 20_270_101, isUsed: true),
      extractedGifticon("expired", expiry: 20_250_101, isUsed: true),
      extractedGifticon("noExpiry", expiry: nil, isUsed: true),
    ])

    #expect(result.sections.map(\.kind) == [.usedGifticons])
    #expect(result.candidateIDs == ["checking", "future", "expired", "noExpiry"])
    #expect(result.sections.first?.candidates.allSatisfy(\.isSelectedByDefault) == true)
    #expect(result.checkingGifticonCount == 0)
  }

  @Test("한 장은 한 섹션에만 든다. 만료된 사용함은 사용함에만 있다")
  func usedWinsOverExpired() {
    let result = Self.sections([
      extractedGifticon("usedExpired", expiry: 20_250_101, isUsed: true),
      extractedGifticon("expired", expiry: 20_250_101),
    ])

    #expect(result.sections.map(\.kind) == [.expiredGifticons, .usedGifticons])
    #expect(result.sections.map { $0.candidates.map(\.id) } == [["expired"], ["usedExpired"]])
  }

  @Test("만료됨은 최근 만료부터, 같은 만료일이면 최신순이고 사용함은 최신순이다")
  func ordering() {
    let result = Self.sections([
      extractedGifticon("oldExpiry", expiry: 20_250_101, created: "2025-01-01T00:00:00Z"),
      extractedGifticon("sameOld", expiry: 20_261_001, created: "2026-09-01T00:00:00Z"),
      extractedGifticon("sameNew", expiry: 20_261_001, created: "2026-09-02T00:00:00Z"),
      extractedGifticon("usedOld", expiry: nil, created: "2026-01-01T00:00:00Z", isUsed: true),
      extractedGifticon("usedNew", expiry: nil, created: "2026-02-01T00:00:00Z", isUsed: true),
    ])

    #expect(result.sections.map { $0.candidates.map(\.id) } == [
      ["sameNew", "sameOld", "oldExpiry"],
      ["usedNew", "usedOld"],
    ])
  }

  @Test("빈 입력과 한쪽만 있는 경우 빈 섹션은 빠진다")
  func emptySectionsAreDropped() {
    #expect(Self.sections([]).isEmpty)
    #expect(Self.sections([extractedGifticon("u", expiry: nil, isUsed: true)]).sections.map(\.kind) == [.usedGifticons])
  }
}
