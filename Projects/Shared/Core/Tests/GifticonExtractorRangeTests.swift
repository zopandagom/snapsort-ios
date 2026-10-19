import Core
import CoreGraphics
import Foundation
import Testing

// GifticonExtractorTests 의 나머지 테스트(연도 보정, 여러 줄에 걸친 기간, 교환처). 파일 길이 한도로 나눴고,
// 도우미(`extract`·`line`·`date`)는 GifticonExtractorTests.swift 에 있다.
// 테스트의 OCR 줄은 지어낸 텍스트다. 실제 기프티콘에서 읽은 텍스트는 넣지 않는다 (docs/CONVENTIONS.md §3).

extension GifticonExtractorTests {
  @Test("연도를 생략한 만료일은 기준일 이후 처음 오는 그 날짜다")
  func infersMissingYear() {
    let october = date(year: 2026, month: 10, day: 18)
    #expect(extract([line("유효기간 12월 31일까지")], referenceDate: october).expiryDate
      == LocalDate(year: 2026, month: 12, day: 31))
    #expect(extract([line("유효기간 1월 5일까지")], referenceDate: october).expiryDate
      == LocalDate(year: 2027, month: 1, day: 5))
    #expect(extract([line("유효기간 10월 18일")], referenceDate: october).expiryDate
      == LocalDate(year: 2026, month: 10, day: 18))
    #expect(extract([line("유효기간 12월 31일")], referenceDate: nil).expiryDate == nil)
  }

  @Test("연도를 생략한 기간은 끝 날짜를 기준일 이후로 정한다")
  func infersMissingYearForRange() {
    let october = date(year: 2026, month: 10, day: 18)
    #expect(extract([line("유효기간 10월 1일 ~ 12월 31일")], referenceDate: october).expiryDate
      == LocalDate(year: 2026, month: 12, day: 31))
    #expect(extract([line("유효기간 10월 1일 ~", y: 0.5), line("12월 31일", y: 0.55)], referenceDate: october).expiryDate
      == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("끝 날짜의 연도를 생략하면 시작 날짜의 연도로 정한다")
  func infersEndYearFromStart() {
    let nextYear = date(year: 2027, month: 3, day: 1)
    #expect(extract([line("유효기간 2026년 1월 1일 ~ 12월 31일")], referenceDate: nextYear).expiryDate
      == LocalDate(year: 2026, month: 12, day: 31))
    #expect(extract([line("유효기간 2026년 1월 1일 ~ 12월 31일")], referenceDate: nil).expiryDate
      == LocalDate(year: 2026, month: 12, day: 31))
    #expect(extract([line("2026년 1월 1일 ~ 12월 31일까지")], referenceDate: nextYear).expiryDate
      == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("연도를 생략한 2월 29일은 다음 윤년의 날짜다")
  func infersLeapDay() {
    #expect(extract([line("유효기간 2월 29일까지")]).expiryDate == LocalDate(year: 2028, month: 2, day: 29))
  }

  @Test(
    "같은 줄에서 기간의 끝을 읽지 못하면 시작 날짜를 만료일로 쓰지 않는다",
    arguments: ["유효기간 2026.01.01 ~ 12.31", "유효기간 2026.01.01 ~ 2026.02.30", "유효기간 2026.01.01부터 ~ 31"]
  )
  func ignoresRangeStartWithUnreadEnd(_ text: String) {
    #expect(extract([line(text)]).expiryDate == nil)
  }
}

extension GifticonExtractorTests {
  @Test("라벨 줄의 기간 시작보다 이른 '까지' 기한은 만료일로 쓰지 않는다")
  func ignoresSuffixedDateBeforeLabelRangeStart() {
    let info = extract([line("유효기간 2026.11.01 ~", y: 0.3), line("주문 취소는 2026.10.20까지", y: 0.7)])
    #expect(info.expiryDate == nil)
  }

  @Test("값 줄에서 시작한 기간의 시작보다 이른 '까지' 기한은 만료일로 쓰지 않는다")
  func ignoresSuffixedDateBeforeValueRangeStart() {
    let info = extract([
      line("유효기간", y: 0.3),
      line("2026.11.01 ~", y: 0.335),
      line("주문 취소는 2026.10.20까지", y: 0.7),
    ])
    #expect(info.expiryDate == nil)
  }

  @Test("'부터'로 끝난 줄은 기간이 다음 줄로 넘어간 것이다")
  func readsRangeContinuedAfterStartSuffix() {
    let info = extract([line("유효기간 2026.01.01부터", y: 0.5), line("2026.12.31까지", y: 0.55)])
    #expect(info.expiryDate == LocalDate(year: 2026, month: 12, day: 31))
    #expect(extract([line("유효기간 2026.01.01부터")]).expiryDate == nil)
  }

  @Test("'부터' 뒤의 끝 날짜를 읽지 못하면 시작 날짜를 만료일로 쓰지 않는다")
  func ignoresRangeStartBeforeUnreadEndAfterStartSuffix() {
    #expect(extract([line("유효기간 2026.01.01부터 12.31까지")]).expiryDate == nil)
  }

  @Test("라벨의 기간 끝을 읽지 못하면 다른 '까지' 기한도 만료일로 쓰지 않는다")
  func ignoresSuffixedDatesWhenLabelRangeIsUnread() {
    #expect(extract([line("유효기간 2026.01.01 ~ 12.31 (취소 2026.01.07까지)")]).expiryDate == nil)
    #expect(extract([line("유효기간 2026.01.01 ~ 12.31", y: 0.3), line("주문 취소는 2026.01.07까지", y: 0.7)]).expiryDate
      == nil)
  }

  @Test("앞 라벨 줄의 기간 시작보다 이르거나 앞 라벨 줄이 만료일을 알 수 없으면 뒤 라벨 줄의 날짜를 쓰지 않는다")
  func appliesEarlierLabelLineToLaterLabelLine() {
    #expect(extract([line("유효기간 구매일로부터 1년", y: 0.3), line("사용기간 2026.10.01", y: 0.7)]).expiryDate == nil)
    #expect(
      extract(
        [line("유효기간 2026.01.01 ~", y: 0.3), line("사용기간 12월 31일", y: 0.7)],
        referenceDate: date(year: 2027, month: 3, day: 1)
      )
      .expiryDate == LocalDate(year: 2026, month: 12, day: 31)
    )
    #expect(extract([line("유효기간 2026.11.01 ~", y: 0.3), line("사용기간 2026.10.01", y: 0.7)]).expiryDate == nil)
    #expect(extract([line("유효기간 2026.01.01 ~ 12.31", y: 0.3), line("사용기간 2026.10.01", y: 0.7)]).expiryDate == nil)
    #expect(extract([line("유효기간 2026.11.01 ~", y: 0.3), line("사용기간 2026.12.31", y: 0.7)]).expiryDate
      == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("기간 시작이 여럿이면 가장 늦은 시작보다 이른 '까지' 기한은 쓰지 않는다")
  func usesLatestRangeStart() {
    let info = extract([
      line("유효기간 2026.11.01 ~", y: 0.3),
      line("2026.10.01 ~", y: 0.335),
      line("취소 2026.10.20까지", y: 0.7),
    ])
    #expect(info.expiryDate == nil)
  }

  @Test("연도를 생략한 값 줄·'까지' 기한은 앞 줄 기간 시작의 연도로 정한다")
  func infersYearFromPreviousLineRangeStart() {
    let nextYear = date(year: 2027, month: 3, day: 1)
    #expect(extract([line("유효기간 2026년 1월 1일 ~", y: 0.5), line("12월 31일", y: 0.55)], referenceDate: nextYear)
      .expiryDate == LocalDate(year: 2026, month: 12, day: 31))
    #expect(extract([line("유효기간 2026년 1월 1일 ~", y: 0.3), line("12월 31일까지", y: 0.7)], referenceDate: nextYear)
      .expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("라벨 줄에서 기간의 끝을 읽지 못하면 아래 줄의 날짜를 값으로 쓰지 않는다")
  func ignoresLineBelowUnreadLabelRange() {
    let info = extract([line("유효기간 2026.01.01 ~ 12.31", y: 0.5), line("2026.01.01 발행", y: 0.55)])
    #expect(info.expiryDate == nil)
  }

  @Test(
    "라벨 줄 기간 뒤에 붙은 다른 항목의 날짜·'까지' 기한은 쓰지 않는다",
    arguments: [
      "유효기간 2026.01.01 ~ 2026.12.31 (취소 2026.01.07까지)",
      "유효기간 2026.12.31 (교환 2026.10.01~2026.10.07까지)",
      "유효기간 2026.12.31 2026.10.07까지",
      "유효기간 2026년 1월 1일 ~ 12월 31일 2026.10.01",
    ]
  )
  func ignoresOtherDatesOnLabelLine(_ text: String) {
    #expect(extract([line(text)]).expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("교환처는 라벨 뒤 텍스트를 구분 기호 없이 그대로 쓴다")
  func readsRedemptionPlaceOnSameLine() {
    #expect(extract([line("교환처: 커피 전문점")]).redemptionPlace == "커피 전문점")
    #expect(extract([line("사용처 | 편의점")]).redemptionPlace == "편의점")
  }

  @Test("라벨이 없으면 아무것도 찾지 않는다")
  func returnsNilWithoutLabels() {
    let info = extract([line("아메리카노 T"), line("1234 5678 9012")])
    #expect(info == GifticonInfo(expiryDate: nil, redemptionPlace: nil))
    #expect(extract([]) == GifticonInfo(expiryDate: nil, redemptionPlace: nil))
  }

  @Test("값 줄에 날짜 없는 설명만 있으면 다른 '까지' 기한도 만료일로 쓰지 않는다")
  func ignoresSuffixedDateWhenValueLineIsDescription() {
    let info = extract([
      line("유효기간", x: 0.1, y: 0.3, width: 0.2),
      line("구매일로부터 1년", x: 0.5, y: 0.3, width: 0.4),
      line("환불 2026.10.20까지", y: 0.7),
    ])
    #expect(info.expiryDate == nil)
  }

  @Test("연도 없는 월.일을 줄표로 이은 기간을 두 자리 연도 날짜로 읽지 않는다", arguments: ["01.01 - 12.31", "12/01-12/31"])
  func ignoresTwoDigitYearLookalike(_ range: String) {
    #expect(extract([line("유효기간 \(range)")]).expiryDate == nil)
  }

  @Test("조사가 붙은 라벨 단어로 시작하는 안내문은 라벨로 보지 않는다")
  func ignoresLabelWordFollowedByParticle() {
    let info = extract([line("유효기간이 지난 상품은 환불되지 않습니다", y: 0.3), line("2026.12.31까지 사용 가능", y: 0.7)])
    #expect(info.expiryDate == LocalDate(year: 2026, month: 12, day: 31))
    #expect(extract([line("교환처의 사정에 따라 변경될 수 있습니다")]).redemptionPlace == nil)
  }

  @Test("이어짐 기호가 다음 줄 맨 앞으로 넘어간 기간은 끝 날짜를 쓴다")
  func readsRangeWithSeparatorOnNextLine() {
    let end = LocalDate(year: 2027, month: 10, day: 17)
    #expect(extract([line("유효기간 2026.10.18", y: 0.5), line("~ 2027.10.17", y: 0.55)]).expiryDate == end)
    #expect(extract([line("유효기간", y: 0.5), line("2026.10.18", y: 0.55), line("~ 2027.10.17", y: 0.6)])
      .expiryDate == end)
    #expect(extract([line("유효기간 2026.10.18", y: 0.5), line("~ 27.10", y: 0.55)]).expiryDate == nil)
    // 오른쪽 같은 높이에 다른 글이 있어도 아래 줄을 본다.
    #expect(
      extract([
        line("유효기간 2026.10.18", x: 0.1, y: 0.5, width: 0.4),
        line("D-365", x: 0.6, y: 0.5, width: 0.2),
        line("~ 2027.10.17", y: 0.55),
      ]).expiryDate == end
    )
  }

  @Test(
    "글이 섞인 글머리표 안내문은 이어진 기간이 아니다",
    arguments: ["- 본 상품은 환불되지 않습니다", "- 1인 1매", "- 3,000원 이상 구매 시", "- 2027.01.31까지 연장 신청 가능"]
  )
  func ignoresBulletNoticeBelowExpiry(_ notice: String) {
    #expect(extract([line("유효기간 2026.12.31", y: 0.5), line(notice, y: 0.55)]).expiryDate
      == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("두 자리 연도에 '년'을 붙인 날짜를 읽는다")
  func readsTwoDigitYearWithYearSuffix() {
    #expect(extract([line("유효기간 26년 12월 31일")]).expiryDate == LocalDate(year: 2026, month: 12, day: 31))
    #expect(extract([line("유효기간 26년 12.31")]).expiryDate == nil)
  }

  @Test("물결표와 끝 날짜의 연도가 함께 빠진 기간은 시작 날짜를 만료일로 쓰지 않는다")
  func ignoresRangeStartBeforeBareMonthDay() {
    #expect(extract([line("유효기간 2026.01.01 12.31")]).expiryDate == nil)
    #expect(extract([line("유효기간 2026.12.31 1매")]).expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("만료일 아래·오른쪽의 줄표로 시작하는 숫자 줄은 이어진 기간이 아니다")
  func ignoresDashNumberLineBelowExpiry() {
    let end = LocalDate(year: 2026, month: 12, day: 31)
    #expect(extract([line("유효기간 2026.12.31", y: 0.5), line("-3,000", y: 0.55)]).expiryDate == end)
    #expect(extract([line("유효기간 2026.01.01 ~ 2026.12.31", y: 0.5), line("- 1", y: 0.55)]).expiryDate == end)
  }

  @Test("라벨 오른쪽 줄에 날짜가 없으면 아래 줄의 값을 읽는다")
  func readsValueBelowWhenSameRowHasNoDate() {
    let info = extract([
      line("유효기간", x: 0.1, y: 0.5, width: 0.2),
      line("D-365", x: 0.5, y: 0.5, width: 0.2),
      line("2026.12.31", y: 0.55),
    ])
    #expect(info.expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("숫자 없는 라벨 단어 안내문은 뒤 라벨 줄과 '까지' 기한을 막지 않는다")
  func doesNotBlockOnNoticeWithoutNumber() {
    let end = LocalDate(year: 2026, month: 12, day: 31)
    #expect(extract([line("* 유효기간 만료 후 환불 불가", y: 0.3), line("유효기간 2026.12.31", y: 0.6)]).expiryDate == end)
    #expect(extract([line("- 유효기간 연장 불가", y: 0.3), line("2026.12.31까지 사용 가능", y: 0.6)]).expiryDate == end)
  }

  @Test("라벨 없는 '까지' 기한에서 연도를 모르는 기한이 연도를 아는 기한보다 늦으면 만료일을 비운다")
  func clearsAmbiguousDeadlinesWithoutYear() {
    // 연도를 모르는 기한이 응모 기한(다음 해로 밀림)인지 만료일인지 알 수 없다.
    #expect(extract([line("이벤트 응모 10월 1일까지", y: 0.4), line("2026.12.31까지 사용 가능", y: 0.5)]).expiryDate == nil)
    #expect(extract([line("12월 31일까지 사용 가능", y: 0.4), line("주문 취소는 2026.10.20까지", y: 0.5)]).expiryDate == nil)
    // 연도를 모르는 기한이 더 이르면 연도를 아는 기한을 쓴다.
    #expect(extract([line("10월 20일까지 취소 가능", y: 0.4), line("2026.12.31까지 사용 가능", y: 0.5)]).expiryDate
      == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("끝이 정해진 만료일 아래의 날짜 글머리 줄은 이어진 기간이 아니다")
  func ignoresDateBulletBelowFixedEnd() {
    let end = LocalDate(year: 2026, month: 12, day: 31)
    #expect(extract([line("유효기간 2026.12.31까지", y: 0.5), line("- 2027.03.31", y: 0.55)]).expiryDate == end)
    #expect(extract([line("유효기간 2026.01.01 ~ 2026.12.31", y: 0.5), line("- 2027.03.31", y: 0.55)]).expiryDate == end)
    #expect(
      extract([line("유효기간 2026.01.01 ~", y: 0.5), line("2026.12.31", y: 0.55), line("- 2027.03.31", y: 0.6)])
        .expiryDate == end
    )
    #expect(
      extract([line("유효기간 ~", y: 0.5), line("2026.12.31", y: 0.55), line("- 2027.03.31", y: 0.6)]).expiryDate == end
    )
    #expect(
      extract([line("유효기간 10월 1일 ~", y: 0.5), line("2026.12.31", y: 0.55), line("- 2027.03.31", y: 0.6)])
        .expiryDate == end
    )
    // 같은 줄의 다른 항목 기한은 끝을 정하지 않는다. 아래 줄로 넘어간 기간의 끝을 쓴다.
    #expect(
      extract([line("유효기간 2026.10.18 (취소 2026.10.20까지)", y: 0.5), line("~ 2027.10.17", y: 0.55)]).expiryDate
        == LocalDate(year: 2027, month: 10, day: 17)
    )
  }

  @Test("앞 줄 기간 시작으로 연도를 정한 '까지' 기한은 연도를 아는 기한으로 본다")
  func treatsDeadlineAnchoredOnRangeStartAsKnownYear() {
    let info = extract(
      [line("유효기간 2026년 1월 1일 ~", y: 0.2), line("12월 31일까지", y: 0.6), line("주문 취소 2026.01.07까지", y: 0.8)],
      referenceDate: date(year: 2027, month: 3, day: 1)
    )
    #expect(info.expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("OCR 이 공백을 빼먹어 라벨 뒤에 조사 같은 글자로 시작하는 값이 붙어도 라벨이다")
  func readsLabelFollowedByParticleLikeValue() {
    #expect(extract([line("사용처이마트")]).redemptionPlace == "이마트")
    #expect(extract([line("교환처에뛰드")]).redemptionPlace == "에뛰드")
  }

  @Test("다음 줄로 넘어간 기간의 끝을 못 찾으면 날짜 앞에 글이 있는 다른 기한을 만료일로 쓰지 않는다")
  func ignoresOtherDeadlineAfterUnfinishedRangeStart() {
    let info = extract([line("유효기간 2026.10.01 ~", y: 0.3), line("주문 취소는 2026.10.07까지", y: 0.7)])
    #expect(info.expiryDate == nil)
  }

  @Test("연도가 적힌 기간 시작이 달력에 없으면 연도를 생략한 끝 날짜를 정하지 않는다")
  func ignoresYearlessEndAfterInvalidAnchor() {
    let info = extract([line("유효기간 2026.02.30 ~ 12월 31일")], referenceDate: date(year: 2027, month: 3, day: 1))
    #expect(info.expiryDate == nil)
  }
}
