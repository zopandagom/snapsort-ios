import Foundation
import Testing
@testable import LibraryFeature

/// 영수증 목록의 날짜 형식이 섹션을 나눈 달력의 시간대를 쓰는지. 2026-11-01T03:59:59Z 는
/// 뉴욕(EDT) 2026-10-31 23:59:59, 서울 2026-11-01 12:59:59 다.
struct ReceiptDateTextTests {
  private let date = Date(timeIntervalSince1970: 1_793_505_599)
  private let korean = Locale(identifier: "ko_KR")

  @Test("월 머리 형식은 섹션을 나눈 달력의 시간대로 달을 쓴다")
  func monthUsesCalendarTimeZone() {
    let newYork = ReceiptDateText.monthStyle(calendar: .newYork)
    let seoul = ReceiptDateText.monthStyle(calendar: .seoul)

    #expect(self.date.formatted(newYork.locale(self.korean)) == "2026년 10월")
    #expect(self.date.formatted(seoul.locale(self.korean)) == "2026년 11월")
    #expect(newYork.timeZone == Calendar.newYork.timeZone)
    #expect(seoul.timeZone == Calendar.seoul.timeZone)
    #expect(newYork.calendar == Calendar.newYork)
  }

  @Test("줄 날짜 형식도 같은 달력의 시간대로 날짜를 쓴다")
  func dayUsesCalendarTimeZone() {
    let newYork = ReceiptDateText.dayStyle(calendar: .newYork)
    let seoul = ReceiptDateText.dayStyle(calendar: .seoul)

    #expect(self.date.formatted(newYork.locale(self.korean)) == "2026년 10월 31일")
    #expect(self.date.formatted(seoul.locale(self.korean)) == "2026년 11월 1일")
    #expect(newYork.timeZone == Calendar.newYork.timeZone)
  }
}
