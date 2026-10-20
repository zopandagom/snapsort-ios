import CoreGraphics
import Foundation
import Testing
@testable import Core

// GifticonExtractorTests 의 나머지 테스트(이웃 줄 이어짐 표시 뒤 글, 공백 없는 잇는 말, 시각 표기 변형). 파일 길이 한도로 나눴고,
// 도우미(`extract`·`line`·`date`)는 GifticonExtractorTests.swift 에 있다.
// 테스트의 OCR 줄은 지어낸 텍스트다. 실제 기프티콘에서 읽은 텍스트는 넣지 않는다 (docs/CONVENTIONS.md §3).

extension GifticonExtractorTests {
  /// 기간 시작 줄 아래에 `below` 를 둔 이미지의 만료일.
  func expiryBelowStart(_ below: String, start: String = "유효기간 2026.10.18") -> LocalDate? {
    extract([line(start, y: 0.5), line(below, y: 0.55)]).expiryDate
  }

  @Test(
    "기간 표시 이웃 줄 날짜 뒤에 다른 항목 안내가 있으면 비운다",
    arguments: [
      "~ 2027.01.31까지 연장 신청 가능",
      "until 2027.01.31 (취소 2027.01.07까지)",
      "~ 2027.03.31 연장 신청 시 2027.01.31까지",
      "~ 2027.03.31 (취소 2027.01.07까지)",
    ]
  )
  func ignoresRangeMarkerLineWithOtherNotice(_ below: String) {
    #expect(self.expiryBelowStart(below) == nil)
  }

  @Test(
    "기간 표시 이웃 줄 날짜 뒤 기간 끝 말은 이어진 기간의 끝이다",
    arguments: ["~ 2027.01.31까지 사용 가능", "~ 2027.01.31까지 교환 가능", "~ 2027.01.31 자정", "~ 2027.01.31까지만 유효"]
  )
  func readsRangeMarkerLineWithRangeEndWords(_ below: String) {
    #expect(self.expiryBelowStart(below) == LocalDate(year: 2027, month: 1, day: 31))
  }

  @Test(
    "기간 끝 말 뒤의 존댓말 어미는 글로 세지 않는다",
    arguments: [
      "~ 2027.01.31까지 사용 가능합니다", "~ 2027.01.31까지 이용 가능합니다.", "~ 2027.01.31까지입니다", "~ 2027.01.31까지 사용 가능해요",
    ]
  )
  func readsRangeMarkerLineWithSentenceEnding(_ below: String) {
    #expect(self.expiryBelowStart(below) == LocalDate(year: 2027, month: 1, day: 31))
  }

  @Test("어미가 붙어도 다른 항목 안내는 끝이 아니다", arguments: ["~ 2027.01.31까지 연장 신청 가능합니다", "~ 2027.01.31 이후 환불 불가합니다"])
  func ignoresOtherNoticeWithSentenceEnding(_ below: String) {
    #expect(self.expiryBelowStart(below) == nil)
  }

  @Test("줄표 이웃 줄 날짜 뒤 기간 끝 말은 이어진 기간의 끝이다")
  func readsDashLineWithRangeEndWords() {
    #expect(self.expiryBelowStart("- 2027.01.31까지 사용 가능") == LocalDate(year: 2027, month: 1, day: 31))
  }

  @Test("줄표 이웃 줄도 기간 끝 말 뒤 어미는 글로 세지 않는다")
  func readsDashLineWithSentenceEnding() {
    #expect(self.expiryBelowStart("- 2027.01.31까지 사용 가능합니다") == LocalDate(year: 2027, month: 1, day: 31))
  }

  @Test("줄표 글머리표 안내문은 어미가 붙어도 이어짐이 아니다", arguments: ["- 2027.01.31까지 연장 신청 가능합니다", "- 본 상품은 환불되지 않습니다"])
  func ignoresDashNoticeWithSentenceEnding(_ below: String) {
    #expect(self.expiryBelowStart(below, start: "유효기간 2026.12.31") == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("공백 없는 영문 잇는 말도 이웃 줄 표시다")
  func readsJoinerWithoutSpaceOnBelowLine() {
    #expect(self.expiryBelowStart("to2026.12.31") == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("잇는 말로 시작하는 영문 단어는 표시가 아니다", arguments: ["today only", "total 3", "tomorrow", "tonight", "to 3명"])
  func ignoresWordStartingWithJoiner(_ below: String) {
    #expect(self.expiryBelowStart(below, start: "유효기간 2026.12.31") == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test(
    "AM·PM 시각을 건너뛰고 기간을 잇는다",
    arguments: [
      "유효기간 2026.01.01 12:00 AM ~ 2026.12.31 11:59 PM",
      "유효기간 2026.01.01 12:00 a.m. ~ 2026.12.31 11:59 p.m.",
      "유효기간 2026.01.01 12:00am - 2026.12.31 11:59pm",
    ]
  )
  func linksRangeAcrossEnglishTime(_ text: String) {
    #expect(extract([line(text)]).expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test(
    "오전·오후 시각을 건너뛰고 기간을 잇는다",
    arguments: ["유효기간 2026.01.01 오전 00:00 ~ 2026.12.31 오후 11:59", "유효기간 2026.01.01 오전 9시 ~ 2026.12.31 오후 11시"]
  )
  func linksRangeAcrossKoreanTime(_ text: String) {
    #expect(extract([line(text)]).expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("시각 뒤 까지도 기한이다", arguments: ["2026.12.31 11:59 PM까지 사용", "2026.12.31 자정까지"])
  func readsDeadlineAfterTime(_ text: String) {
    #expect(extract([line(text)]).expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("줄표 이웃 줄의 AM·PM 시각은 글이 아니다")
  func readsDashLineWithEnglishTime() {
    #expect(self.expiryBelowStart("- 2026.12.31 11:59 PM") == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("숫자와 붙지 않은 am·pm 은 시각이 아니다")
  func ignoresAmPmInsideWord() {
    #expect(self.expiryBelowStart("- 2027.01.31 game") == LocalDate(year: 2026, month: 10, day: 18))
  }

  @Test(
    "분 없는 AM·PM 시각을 건너뛰고 기간을 잇는다",
    arguments: [
      "유효기간 2026.01.01 12AM ~ 2026.12.31 11PM",
      "유효기간 2026.01.01 12 a.m. ~ 2026.12.31 11 p.m.",
      "유효기간 2026.01.01 AM 9 ~ 2026.12.31 PM 11",
    ]
  )
  func linksRangeAcrossHourOnlyEnglishTime(_ text: String) {
    #expect(extract([line(text)]).expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("물결표 이웃 줄의 분 없는 AM·PM 시각은 기간 끝 말 자리를 막지 않는다")
  func readsTildeLineWithHourOnlyEnglishTime() {
    #expect(self.expiryBelowStart("~ 2027.01.31 11PM") == LocalDate(year: 2027, month: 1, day: 31))
  }

  @Test("줄표 이웃 줄의 분 없는 AM·PM 시각도 같다")
  func readsDashLineWithHourOnlyEnglishTime() {
    #expect(self.expiryBelowStart("- 2027.01.31 11PM") == LocalDate(year: 2027, month: 1, day: 31))
  }

  @Test("영문 시각 말 midnight·noon 을 건너뛴다")
  func skipsEnglishTimeWords() {
    #expect(extract([line("유효기간 2026.01.01 midnight ~ 2026.12.31 midnight")]).expiryDate
      == LocalDate(year: 2026, month: 12, day: 31))
    #expect(self.expiryBelowStart("~ 2027.01.31 noon") == LocalDate(year: 2027, month: 1, day: 31))
  }

  @Test("날짜 바로 뒤 pm2.5 는 시각이 아니다")
  func ignoresFineDustNotationAfterDate() {
    #expect(self.expiryBelowStart("~ 2027.01.31 pm2.5") == nil)
    #expect(extract([line("유효기간 2026.12.31 pm2.5 나쁨")]).expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("앞에 붙은 PM 은 뒤 날짜의 앞자리를 먹지 않는다")
  func leavesDateAfterLeadingPm() {
    #expect(GifticonExtractor.skippingWeekdayAndTime("pm2026.12.31") == "pm2026.12.31")
    #expect(GifticonExtractor.skippingWeekdayAndTime("pm2.5") == "pm2.5")
    #expect(GifticonExtractor.skippingWeekdayAndTime("pm11~2026") == "~2026")
  }

  @Test("숫자 뒤 am 으로 시작하는 단어와 pm25 는 시각이 아니다")
  func leavesWordStartingWithAm() {
    #expect(GifticonExtractor.skippingWeekdayAndTime("2amazon") == "2amazon")
    #expect(GifticonExtractor.skippingWeekdayAndTime("pm25") == "pm25")
    #expect(self.expiryBelowStart("~ 2027.01.31 2 amazon") == nil)
  }

  @Test("줄표 이웃 줄의 pm25·pm2.5 는 시각이 아니다", arguments: ["- 2027.01.31 pm25", "- 2027.01.31 pm2.5"])
  func ignoresDashLineWithFineDustNotation(_ below: String) {
    #expect(self.expiryBelowStart(below) == LocalDate(year: 2026, month: 10, day: 18))
  }

  @Test(
    "홀로 쓴 시각 말은 기간 끝을 막지 않는다",
    arguments: ["- 2027.01.31 오후", "- 2027.01.31 PM", "~ 2027.01.31 오후", "~ 2027.01.31 midnight까지"]
  )
  func readsLineWithStandaloneTimeWord(_ below: String) {
    #expect(self.expiryBelowStart(below) == LocalDate(year: 2027, month: 1, day: 31))
  }

  @Test("영문 단어 속 am·pm 은 시각 말이 아니다")
  func ignoresAmPmWordAfterDate() {
    #expect(self.expiryBelowStart("- 2027.01.31 amazon") == LocalDate(year: 2026, month: 10, day: 18))
    #expect(self.expiryBelowStart("~ 2027.01.31 amazon") == nil)
  }

  @Test("줄표 이웃 줄의 영문 날짜는 시각이 붙어도 이어진 기간이라 비운다")
  func ignoresStartBeforeDashEnglishDateWithTime() {
    #expect(self.expiryBelowStart("- Dec 31st, 2026 11:59 PM") == nil)
  }

  @Test(
    "앞에 붙은 AM·PM 시 뒤 줄표 다음이 날짜면 시각이다",
    arguments: ["유효기간 2026.01.01 AM 9 - 2026.12.31 PM 11", "유효기간 2026.01.01 AM 9 - 12월 31일"]
  )
  func linksRangeAcrossLeadingAmPmBeforeDash(_ text: String) {
    #expect(extract([line(text)]).expiryDate == LocalDate(year: 2026, month: 12, day: 31))
  }

  @Test("앞에 붙은 PM 뒤 월.일은 시각이 아니다")
  func leavesMonthDayAfterLeadingPm() {
    #expect(GifticonExtractor.skippingWeekdayAndTime("pm12-31") == "pm12-31")
    #expect(GifticonExtractor.skippingWeekdayAndTime("pm11-3") == "pm11-3")
  }
}
