import Core
import CoreGraphics
import Foundation
import Testing

/// 테스트의 OCR 줄은 지어낸 텍스트다. 실제 기프티콘에서 읽은 텍스트는 넣지 않는다 (docs/CONVENTIONS.md §3).
struct GifticonExtractorTests {
  @Test(
    "라벨 줄의 여러 날짜 형식에서 만료일을 읽는다",
    arguments: [
      "유효기간 2026.12.31",
      "유효기간: 2026-12-31",
      "유효기간 2026/12/31",
      "유효기간 2026년 12월 31일",
      "유효기간 2026. 12. 31",
      "유효기간 26.12.31",
      "사용기한 ~2026.12.31",
      "만료일 2026.12.31 까지",
    ]
  )
  func readsDateFormats(_ text: String) {
    #expect(extract([line(text)]).expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("기간이면 끝 날짜를 만료일로 쓴다")
  func usesRangeEnd() {
    let info = extract([line("유효기간 2026.01.01 ~ 2026.12.31")])
    #expect(info.expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("기간이 다음 줄로 넘어가면 다음 줄의 끝 날짜를 쓴다", arguments: ["~", "～", "∼", "〜", "-", "–", "—"])
  func usesRangeEndOnNextLine(_ separator: String) {
    let info = extract([
      line("유효기간 2026.01.01 \(separator)", y: 0.5),
      line("2026.12.31", y: 0.55),
    ])
    #expect(info.expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test(
    "날짜 뒤에 요일·시각이 붙어도 만료일을 읽는다",
    arguments: [
      "유효기간 2026.12.31 23:59",
      "유효기간 2026.01.01 00:00 ~ 2026.12.31 23:59",
      "유효기간 2026년 12월 31일 23시 59분",
      "2026.12.31 23:59 까지",
      "2026.12.31까지",
      "2026.12.31(목)까지",
      "~2026년 12월 31일(목) 23:59 까지",
      "유효기간 2026.01.01(목) ~ 2026.12.31(목)",
    ]
  )
  func readsDateFollowedByTime(_ text: String) {
    #expect(extract([line(text)]).expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test(
    "물결·줄표 변형이나 공백만으로 이어진 두 날짜는 기간으로 보고 끝 날짜를 쓴다",
    arguments: ["~", "～", "∼", "〜", "-", "–", "—", ""]
  )
  func readsRangeWithSeparatorVariants(_ separator: String) {
    let info = extract([line("유효기간 2026.01.01 \(separator) 2026.12.31")])
    #expect(info.expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test(
    "라벨 줄에 기간이 아닌 다른 날짜가 이어 나와도 만료일을 쓴다",
    arguments: [
      "유효기간 2026.12.31까지 주문일 2026.10.01",
      "유효기간 2026.12.31 주문일 2026.10.01",
      "유효기간 2026.01.01 ~ 2026.12.31 발행일 2026.10.01",
      "유효기간 2026.01.01 ~ 2026.12.31 2026.10.01",
      "유효기간 2026.12.31 2026.10.01",
      "만료일자 2026.12.31",
    ]
  )
  func ignoresLaterUnrelatedDateOnLabelLine(_ text: String) {
    #expect(extract([line(text)]).expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("'부터'로 이은 기간은 끝 날짜를 쓴다", arguments: ["2026.01.01부터 2026.12.31", "2026.01.01 부터 ~ 2026.12.31"])
  func readsRangeJoinedByStartSuffix(_ range: String) {
    #expect(extract([line("유효기간 \(range)")]).expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("라벨 뒤에 날짜 없는 글이 있으면 아래 줄의 날짜를 값으로 쓰지 않는다")
  func ignoresLineBelowLabelFollowedByText() {
    // 설명문 아래의 발행일, 표 머리 줄 아래 두 열은 어느 날짜가 만료일인지 알 수 없다. 틀린 만료일보다 비워 둔다.
    #expect(extract([line("유효기간 발행일로부터 1년", y: 0.5), line("2026.10.01 발행", y: 0.55)]).expiryDate == nil)
    #expect(extract([line("유효기간 주문일", y: 0.5), line("2026.12.31 2026.10.01", y: 0.55)]).expiryDate == nil)
    #expect(extract([line("유효기간 발행일 ~", y: 0.5), line("2026.10.01", y: 0.55)]).expiryDate == nil)
    #expect(extract([line("유효기간 주문일 2026.10.01 ~", y: 0.5), line("2026.12.31", y: 0.55)]).expiryDate == nil)
    #expect(extract([line("유효기간 2026.12.31 주문일 2026.10.01 ~", y: 0.5), line("2026.10.07", y: 0.55)]).expiryDate == nil)
    #expect(extract([line("유효기간 2026.12.31 2026.10.01 ~", y: 0.5), line("2026.10.07", y: 0.55)]).expiryDate == nil)
    #expect(extract([line("유효기간 구매일로부터 1년", y: 0.3), line("환불 2026.10.20까지", y: 0.7)]).expiryDate == nil)
  }

  @Test("값 줄이 다른 항목의 날짜면 만료일로 쓰지 않는다")
  func ignoresOtherFieldOnValueLine() {
    #expect(extract([line("유효기간", y: 0.5), line("주문일 2026.10.01 ~ 2026.10.07까지", y: 0.55)]).expiryDate == nil)
    #expect(extract([line("유효기간", y: 0.5), line("주문일 2026.10.01", y: 0.55)]).expiryDate == nil)
    #expect(extract([line("유효기간 2026.11.01 ~", y: 0.5), line("주문일 2026.10.01", y: 0.55)]).expiryDate == nil)
  }

  @Test("다음 줄로 넘어간 기간의 끝 날짜가 시작 날짜보다 이르면 쓰지 않는다")
  func ignoresContinuedEndBeforeStart() {
    #expect(extract([line("유효기간 2026.11.01 ~", y: 0.5), line("2026.10.01", y: 0.55)]).expiryDate == nil)
  }

  @Test("값 줄도 기간이 다음 줄로 넘어가면 시작 날짜를 만료일로 쓰지 않는다")
  func ignoresRangeStartOnValueLine() {
    let info = extract([
      line("유효기간", y: 0.5),
      line("2026.01.01 ~", y: 0.55),
      line("2026.12.31", y: 0.6),
    ])
    #expect(info.expiryDate == nil)
  }

  @Test("안내문 속 라벨 단어는 라벨로 보지 않는다")
  func ignoresLabelWordsInsideSentences() {
    let info = extract([
      line("제휴사(교환처) 사정에 따라 변경될 수 있습니다", y: 0.5),
      line("상품의 유효기간 2026.12.31 이후에는 연장 불가", y: 0.6),
    ])
    #expect(info == GifticonInfo(expiryDate: nil, redemptionPlace: nil))
    #expect(extract([line("[교환처] 편의점")]).redemptionPlace == "편의점")
    #expect(extract([line("■ 유효기간 : 2026.12.31")]).expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("다른 라벨이 있는 줄은 값으로 고르지 않는다")
  func skipsLabelLinesAsValues() {
    // 교환처가 로고라 읽은 글자가 없고 바로 아래가 유효기간 줄이다.
    let logoPlace = extract([line("교환처", y: 0.5), line("유효기간 2026.12.31", y: 0.55)])
    #expect(logoPlace.redemptionPlace == nil)
    #expect(logoPlace.expiryDate == LocalDate(year: 2026, month: 12, day: 31))

    // 두 라벨이 나란히 있고 값은 각 라벨 아래에 있다.
    let sideBySide = extract([
      line("유효기간", x: 0.1, y: 0.5, width: 0.2),
      line("교환처", x: 0.5, y: 0.5, width: 0.2),
      line("2026.12.31", x: 0.1, y: 0.55, width: 0.3),
      line("편의점", x: 0.5, y: 0.55, width: 0.2),
    ])
    #expect(sideBySide.expiryDate == LocalDate(year: 2026, month: 12, day: 31))
    #expect(sideBySide.redemptionPlace == "편의점")
  }

  @Test("OCR 이 라벨을 띄워 읽어도 찾는다")
  func readsSpacedLabel() {
    let info = extract([line("유 효 기 간 2026.12.31"), line("교 환 처 : 카페", y: 0.6)])
    #expect(info.expiryDate == LocalDate(year: 2026, month: 12, day: 31))
    #expect(info.redemptionPlace == "카페")
  }

  @Test("라벨 오른쪽 같은 높이의 줄에서 값을 읽는다")
  func readsValueOnSameRow() {
    let info = extract([
      line("교환처", x: 0.1, y: 0.5, width: 0.2),
      line("편의점", x: 0.5, y: 0.5, width: 0.3),
      line("유효기간", x: 0.1, y: 0.6, width: 0.2),
      line("2026년 12월 31일", x: 0.5, y: 0.6, width: 0.4),
    ])
    #expect(info.redemptionPlace == "편의점")
    #expect(info.expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("라벨 바로 아래 줄에서 값을 읽는다")
  func readsValueBelow() {
    let info = extract([
      line("교환처", y: 0.5),
      line("빵집", y: 0.55),
      line("유효기간", y: 0.6),
      line("2026.12.31", y: 0.65),
    ])
    #expect(info.redemptionPlace == "빵집")
    #expect(info.expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("라벨에서 멀리 떨어진 아래 줄은 값으로 보지 않는다")
  func ignoresDistantLineBelow() {
    let info = extract([line("유효기간", y: 0.3), line("2026.12.31", y: 0.6)])
    #expect(info.expiryDate == nil)
  }

  @Test("발행일·주문일처럼 라벨이 없는 날짜는 만료일로 쓰지 않는다")
  func ignoresUnlabeledDates() {
    let info = extract([
      line("주문일 2026.10.01", y: 0.4),
      line("유효기간 2027.10.01", y: 0.5),
    ])
    #expect(info.expiryDate == LocalDate(year: 2027, month: 10, day: 1))
    #expect(extract([line("발행일 2026.10.01")]).expiryDate == nil)
  }

  @Test("라벨이 없어도 날짜 뒤에 '까지'가 붙으면 만료일로 쓴다")
  func readsDateWithSuffix() {
    let info = extract([line("발행일 2026.10.01", y: 0.4), line("2026.12.31 까지 사용 가능", y: 0.5)])
    #expect(info.expiryDate == LocalDate(year: 2026, month: 12, day: 31))
    #expect(extract([line("2026년 12월 31일까지 사용 가능")]).expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("기간이 다음 줄로 넘어갔는데 끝 날짜를 못 찾으면 시작 날짜를 만료일로 쓰지 않는다")
  func ignoresRangeStartWithoutEnd() {
    #expect(extract([line("유효기간 2026.01.01 ~")]).expiryDate == nil)
    let info = extract([
      line("유효기간 2026.01.01 ~", y: 0.3),
      line("2026.12.31 까지", y: 0.7),
    ])
    #expect(info.expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("기기 달력이 일본력이어도 연도를 생략한 만료일은 서기 연도다")
  func infersMissingYearWithJapaneseCalendar() throws {
    var japanese = Calendar(identifier: .japanese)
    japanese.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
    let info = GifticonExtractor.extract(
      from: [line("유효기간 12월 31일까지")],
      referenceDate: date(year: 2026, month: 10, day: 18),
      calendar: japanese
    )
    #expect(info.expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("라벨 없이 '까지' 기한이 여럿이면 가장 늦은 것을 만료일로 쓴다")
  func usesLatestSuffixedDate() {
    let info = extract([line("주문 취소는 2026.10.20까지", y: 0.4), line("2026.12.31까지 사용 가능", y: 0.5)])
    #expect(info.expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("달력에 없는 날짜는 쓰지 않는다")
  func rejectsInvalidDate() {
    #expect(extract([line("유효기간 2026.02.30")]).expiryDate == nil)
    #expect(extract([line("유효기간 2028.02.29")]).expiryDate == LocalDate(year: 2028, month: 2, day: 29))
  }

  @Test("쿠폰 번호 같은 긴 숫자열 안의 숫자는 날짜로 보지 않는다")
  func ignoresDigitsInsideLongNumber() {
    #expect(extract([line("유효기간 1234.2026.12.3199")]).expiryDate == nil)
  }
}

extension GifticonExtractorTests {
  static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
  }()

  /// 테스트의 기본 기준일(이미지 생성 시각).
  static let referenceDate = Self.date(year: 2026, month: 10, day: 18)

  static func date(year: Int, month: Int, day: Int) -> Date {
    self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
  }

  func extract(
    _ lines: [RecognizedTextLine],
    referenceDate: Date? = GifticonExtractorTests.referenceDate
  ) -> GifticonInfo {
    GifticonExtractor.extract(from: lines, referenceDate: referenceDate, calendar: Self.calendar)
  }

  func date(year: Int, month: Int, day: Int) -> Date {
    Self.date(year: year, month: month, day: day)
  }

  func line(
    _ text: String,
    x: CGFloat = 0.1,
    y: CGFloat = 0.5,
    width: CGFloat = 0.8,
    height: CGFloat = 0.03
  ) -> RecognizedTextLine {
    RecognizedTextLine(text: text, confidence: 1, boundingBox: CGRect(x: x, y: y, width: width, height: height))
  }
}
