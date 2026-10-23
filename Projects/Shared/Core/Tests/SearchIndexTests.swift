import Foundation
import Testing
@testable import Core

struct SearchIndexTests {
  private static func entry(
    _ id: String,
    _ lines: [String],
    groups: CaptureGroups? = nil,
    created: TimeInterval = 0
  ) -> SearchEntry {
    SearchEntry(
      asset: ImageAsset(
        id: id,
        creationDate: Date(timeIntervalSince1970: created),
        coordinate: nil,
        pixelWidth: 1170,
        pixelHeight: 2532,
        isScreenshot: true
      ),
      lines: lines,
      captureGroups: groups
    )
  }

  private static func hits(_ entries: [SearchEntry], _ query: String) -> [SearchHit] {
    SearchIndex(entries: entries).hits(for: SearchQuery(query))
  }

  private static func ids(_ entries: [SearchEntry], _ query: String) -> [String] {
    self.hits(entries, query).map(\.id)
  }

  // MARK: 줄 대조

  @Test("낱말은 줄 안 부분 일치이고 대소문자를 구분하지 않는다")
  func substringCaseInsensitive() {
    let entries = [Self.entry("a", ["Americano 4,500원"]), Self.entry("b", ["라떼"])]
    #expect(Self.ids(entries, "americ") == ["a"])
    #expect(Self.ids(entries, "AMERICANO") == ["a"])
    #expect(Self.ids(entries, "4,5") == ["a"])
  }

  @Test("줄 안 공백은 무시한다")
  func ignoresWhitespaceInLines() {
    let entries = [Self.entry("a", ["서울 강남 구 역삼동"])]
    #expect(Self.ids(entries, "강남구") == ["a"])
    #expect(Self.ids(entries, "강남 구") == ["a"])
  }

  @Test("NFD 로 저장된 줄도 NFC 검색어로 찾는다")
  func decomposedLines() {
    let entries = [Self.entry("a", ["쿠팡 주문".decomposedStringWithCanonicalMapping])]
    #expect(Self.ids(entries, "쿠팡") == ["a"])
  }

  @Test("낱말이 서로 다른 줄에 있어도 한 이미지 안에 모두 있으면 맞는다(AND)")
  func andAcrossLines() {
    let entries = [Self.entry("a", ["쿠팡", "운동화"]), Self.entry("b", ["쿠팡", "양말"])]
    #expect(Self.ids(entries, "쿠팡 운동화") == ["a"])
    #expect(Self.ids(entries, "운동화 쿠팡") == ["a"])
  }

  @Test("한 낱말이 두 줄에 걸치면 맞지 않는다")
  func wordDoesNotSpanLines() {
    let entries = [Self.entry("a", ["쿠", "팡"]), Self.entry("b", ["스타벅", "스"])]
    #expect(Self.ids(entries, "쿠팡").isEmpty)
    #expect(Self.ids(entries, "스타벅스").isEmpty)
  }

  @Test("낱말이 하나라도 없으면 그 이미지는 빠진다")
  func missingWordDropsImage() {
    let entries = [Self.entry("a", ["쿠팡 운동화"])]
    #expect(Self.ids(entries, "쿠팡 양말").isEmpty)
  }

  @Test("빈 검색어는 빈 배열이다")
  func emptyQuery() {
    let entries = [Self.entry("a", ["쿠팡"])]
    #expect(Self.hits(entries, "").isEmpty)
    #expect(Self.hits(entries, " \u{3000} ").isEmpty)
  }

  @Test("결과 순서는 entries 순서다")
  func keepsEntryOrder() {
    let entries = [Self.entry("c", ["가"]), Self.entry("a", ["가"]), Self.entry("b", ["가"])]
    #expect(Self.ids(entries, "가") == ["c", "a", "b"])
  }

  @Test("줄이 없거나 빈 이미지는 줄로 맞지 않는다")
  func linelessEntries() {
    let entries = [Self.entry("a", []), Self.entry("b", [""])]
    #expect(Self.ids(entries, "가").isEmpty)
    #expect(SearchIndex(entries: entries).count == 2)
  }

  // MARK: 표시

  @Test("맞은 줄의 정규화 전 원문을 보인다")
  func showsOriginalLine() {
    let entries = [Self.entry("a", ["주문 내역", "Coupang  로켓배송"])]
    #expect(Self.hits(entries, "coupang").first?.match == .line("Coupang  로켓배송"))
  }

  @Test("맞은 낱말 중 가장 앞 줄을 보인다")
  func showsEarliestLine() {
    let entries = [Self.entry("a", ["첫째 abc", "쿠팡 둘째", "셋째 xyz"])]
    #expect(Self.hits(entries, "xyz 둘째").first?.match == .line("쿠팡 둘째"))
    #expect(Self.hits(entries, "xyz 첫째").first?.match == .line("첫째 abc"))
  }

  @Test("빈 줄이 앞에 있어도 줄 번호가 어긋나지 않는다")
  func blankLinesKeepNumbering() {
    let entries = [Self.entry("a", ["", " \u{3000} ", "가나다", "", "라마바"])]
    #expect(Self.hits(entries, "가나다").first?.match == .line("가나다"))
    #expect(Self.hits(entries, "라마바").first?.match == .line("라마바"))
  }

  // MARK: 캡처 묶음 별칭

  @Test("몰은 이름·낱말 별칭·줄 별칭으로 찾고 표의 이름을 보인다")
  func mallAliases() throws {
    let coupang = try CaptureGroups(mall: #require(ShoppingMall(id: "coupang")))
    let entries = [Self.entry("a", ["주문 완료"], groups: coupang)]
    #expect(Self.hits(entries, "coupang").first?.match == .group("쿠팡"))
    #expect(Self.hits(entries, "쿠팡").first?.match == .group("쿠팡"))
    #expect(Self.hits(entries, "로켓배송").first?.match == .group("쿠팡"))
    let daangn = try CaptureGroups(mall: #require(ShoppingMall(id: "daangn")))
    #expect(Self.ids([Self.entry("b", [], groups: daangn)], "당근마켓") == ["b"])
    #expect(Self.ids([Self.entry("b", [], groups: daangn)], "당근") == ["b"])
  }

  @Test("브랜드와 대화 앱 이름으로 찾는다")
  func brandAndChatApp() throws {
    let nike = try CaptureGroups(brand: #require(ShoppingBrand(id: "nike")))
    #expect(Self.hits([Self.entry("a", [], groups: nike)], "NIKE").first?.match == .group("나이키"))
    #expect(Self.hits([Self.entry("a", [], groups: nike)], "나이키").first?.match == .group("나이키"))
    let kakao = CaptureGroups(chatApp: .kakaoTalk)
    #expect(Self.hits([Self.entry("b", [], groups: kakao)], "카카오").first?.match == .group("카카오톡"))
  }

  @Test("지역은 시·도의 모든 별칭과 시·군·구 이름으로 찾고 지역 이름을 보인다")
  func regionAliases() throws {
    let gangnam = try CaptureGroups(regions: [#require(KoreanRegion(id: "seoul:강남구"))])
    let entries = [Self.entry("a", [], groups: gangnam)]
    for query in ["서울", "서울시", "서울특별시", "강남구", "강남"] {
      #expect(Self.hits(entries, query).first?.match == .group("서울 강남구"), "\(query)")
    }
    #expect(Self.ids(entries, "부산").isEmpty)
    let provinceOnly = try CaptureGroups(regions: [#require(KoreanRegion(id: "busan"))])
    #expect(Self.hits([Self.entry("b", [], groups: provinceOnly)], "부산광역시").first?.match == .group("부산"))
  }

  @Test("지역이 여럿이면 어느 쪽 별칭으로도 찾는다")
  func multipleRegions() throws {
    let both = try CaptureGroups(regions: [
      #require(KoreanRegion(id: "seoul:강남구")), #require(KoreanRegion(id: "busan:해운대구")),
    ])
    let entries = [Self.entry("a", [], groups: both)]
    #expect(Self.hits(entries, "해운대").first?.match == .group("부산 해운대구"))
    #expect(Self.hits(entries, "강남").first?.match == .group("서울 강남구"))
  }

  @Test("줄에서 맞은 낱말과 별칭에서 맞은 낱말을 섞어도 AND 로 맞고, 줄이 있으면 줄을 보인다")
  func mixedLineAndAlias() throws {
    let coupang = try CaptureGroups(mall: #require(ShoppingMall(id: "coupang")))
    let entries = [
      Self.entry("a", ["러닝 운동화"], groups: coupang),
      Self.entry("b", ["러닝 운동화"]),
      Self.entry("c", ["양말"], groups: coupang),
    ]
    let hits = Self.hits(entries, "쿠팡 운동화")
    #expect(hits.map(\.id) == ["a"])
    #expect(hits.first?.match == .line("러닝 운동화"))
  }

  @Test("묶음 값이 nil 이면 줄로만 찾는다")
  func noGroupsOnlyLines() {
    let entries = [Self.entry("a", ["주문"], groups: nil)]
    #expect(Self.ids(entries, "쿠팡").isEmpty)
    #expect(Self.ids(entries, "주문") == ["a"])
  }

  @Test("묶음 값 별칭은 도메인과 대화 앱 UI 문구를 대조하지 않는다")
  func doesNotMatchDomainsOrSignatures() throws {
    let coupang = try CaptureGroups(mall: #require(ShoppingMall(id: "coupang")))
    #expect(Self.ids([Self.entry("a", [], groups: coupang)], "coupang.com").isEmpty)
    #expect(Self.ids([Self.entry("b", [], groups: CaptureGroups(chatApp: .kakaoTalk))], "여기까지읽었습니다").isEmpty)
  }

  @Test("별칭 한 개 안에서만 맞는다: 낱말이 두 별칭에 걸치면 맞지 않는다")
  func wordDoesNotSpanAliases() throws {
    let both = try CaptureGroups(regions: [#require(KoreanRegion(id: "seoul:강남구"))])
    // "서울" 과 "강남구" 를 이은 "울강" 은 어느 한 별칭 안에도 없다.
    #expect(Self.ids([Self.entry("a", [], groups: both)], "울강").isEmpty)
  }

  // MARK: reusing

  @Test("reusing: 같은 줄은 같은 결과를 내고, 바뀐 줄은 새 줄로 대조하며, 사라진 이미지는 빠진다")
  func reusingPreviousIndex() {
    let old = SearchIndex(entries: [
      Self.entry("a", ["옛글자"]), Self.entry("b", ["그대로"]), Self.entry("gone", ["옛글자"]),
    ])
    let next = SearchIndex(
      entries: [Self.entry("a", ["새글자"]), Self.entry("b", ["그대로"]), Self.entry("new", ["옛글자"])],
      reusing: old
    )
    #expect(next.count == 3)
    #expect(next.hits(for: SearchQuery("그대로")).map(\.id) == ["b"])
    #expect(next.hits(for: SearchQuery("새글자")).map(\.id) == ["a"])
    #expect(next.hits(for: SearchQuery("옛글자")).map(\.id) == ["new"])
    #expect(next.hits(for: SearchQuery("그대로")) == old.hits(for: SearchQuery("그대로")))
  }

  @Test("reusing: 줄이 같아도 묶음 값이 바뀌면 새 묶음 값으로 대조한다")
  func reusingWithChangedGroups() throws {
    let lines = ["주문"]
    let old = SearchIndex(entries: [Self.entry("a", lines, groups: nil)])
    let coupang = try CaptureGroups(mall: #require(ShoppingMall(id: "coupang")))
    let next = SearchIndex(entries: [Self.entry("a", lines, groups: coupang)], reusing: old)
    #expect(old.hits(for: SearchQuery("쿠팡")).isEmpty)
    #expect(next.hits(for: SearchQuery("쿠팡")).map(\.id) == ["a"])
    let cleared = SearchIndex(entries: [Self.entry("a", lines, groups: nil)], reusing: next)
    #expect(cleared.hits(for: SearchQuery("쿠팡")).isEmpty)
    #expect(cleared.hits(for: SearchQuery("주문")).map(\.id) == ["a"])
  }

  // MARK: 바이트 대조·목록 공유

  @Test("묶음 값이 같은 이미지와 다른 이미지가 섞여도 각자 자기 별칭과 이름으로 맞는다")
  func sharedTermListsKeepOwnTitles() throws {
    let coupang = try CaptureGroups(mall: #require(ShoppingMall(id: "coupang")))
    let nike = try CaptureGroups(brand: #require(ShoppingBrand(id: "nike")))
    let gangnam = try CaptureGroups(regions: [#require(KoreanRegion(id: "seoul:강남구"))])
    let entries = [
      Self.entry("a", [], groups: coupang), Self.entry("b", [], groups: nike), Self.entry("c", [], groups: coupang),
      Self.entry("d", [], groups: gangnam), Self.entry("e", [], groups: nike),
    ]
    #expect(Self.hits(entries, "쿠팡").map(\.id) == ["a", "c"])
    #expect(Self.hits(entries, "나이키").map(\.id) == ["b", "e"])
    #expect(Self.hits(entries, "나이키").first?.match == .group("나이키"))
    #expect(Self.hits(entries, "강남구").map(\.match) == [.group("서울 강남구")])
  }

  @Test("묶음 값이 없는 이미지와 있는 이미지가 섞여도 어긋나지 않는다")
  func mixedWithAndWithoutGroups() throws {
    let coupang = try CaptureGroups(mall: #require(ShoppingMall(id: "coupang")))
    let entries = [
      Self.entry("a", ["주문"]), Self.entry("b", ["주문"], groups: coupang),
      Self.entry("c", ["주문"], groups: .empty), Self.entry("d", ["주문"], groups: coupang),
    ]
    #expect(Self.ids(entries, "쿠팡") == ["b", "d"])
    #expect(Self.ids(entries, "주문 쿠팡") == ["b", "d"])
    #expect(Self.ids(entries, "주문") == ["a", "b", "c", "d"])
  }

  @Test("스칼라 단위로 맞는다: 이모지 조합 안의 글자도 맞는다")
  func scalarLevelMatch() {
    let entries = [Self.entry("a", ["가족 👨\u{200D}👩\u{200D}👧"])]
    #expect(Self.ids(entries, "👩") == ["a"])
  }

  @Test("맞은 곳이 마지막 줄이거나 여러 바이트 글자 뒤여도 줄 번호가 맞는다")
  func lineNumberAfterMultibyte() {
    let entries = [Self.entry("a", ["가나다라", "😀😀", "", "마바사 target"])]
    #expect(Self.hits(entries, "target").first?.match == .line("마바사 target"))
    #expect(Self.hits(entries, "😀").first?.match == .line("😀😀"))
    #expect(Self.hits(entries, "나다").first?.match == .line("가나다라"))
  }

  @Test("reusing: 순서와 종류가 바뀌어도 별칭 목록 번호가 옛 색인을 따라가지 않는다")
  func reusingRenumbersTermLists() throws {
    let coupang = try CaptureGroups(mall: #require(ShoppingMall(id: "coupang")))
    let nike = try CaptureGroups(brand: #require(ShoppingBrand(id: "nike")))
    let gangnam = try CaptureGroups(regions: [#require(KoreanRegion(id: "gyeonggi:성남시"))])
    let old = SearchIndex(entries: [Self.entry("a", ["x"], groups: coupang), Self.entry("b", ["y"], groups: nike)])
    let next = SearchIndex(
      entries: [
        Self.entry("c", ["z"], groups: gangnam),
        Self.entry("b", ["y"], groups: nike),
        Self.entry("a", ["x"], groups: coupang),
      ],
      reusing: old
    )
    #expect(next.hits(for: SearchQuery("쿠팡")).map(\.id) == ["a"])
    #expect(next.hits(for: SearchQuery("쿠팡")).first?.match == .group("쿠팡"))
    #expect(next.hits(for: SearchQuery("나이키")).map(\.id) == ["b"])
    #expect(next.hits(for: SearchQuery("성남")).map(\.id) == ["c"])
  }
}
