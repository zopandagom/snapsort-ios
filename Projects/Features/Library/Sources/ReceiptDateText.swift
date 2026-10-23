import Foundation

/// 영수증 목록의 날짜 형식. 섹션을 나눈 달력(`ReceiptListModel.calendar`)의 달력 체계·시간대로 형식화해,
/// 머리의 달이 섹션의 달과 같고 줄의 날짜가 그 섹션 안에 든다. 로캘은 정하지 않는다(화면 환경 로캘).
enum ReceiptDateText {
  /// 월 섹션 머리(예: "2026년 10월").
  static func monthStyle(calendar: Calendar) -> Date.FormatStyle {
    self.styled(.dateTime.year().month(.wide), calendar: calendar)
  }

  /// 줄의 날짜(예: "2026년 10월 15일").
  static func dayStyle(calendar: Calendar) -> Date.FormatStyle {
    self.styled(.dateTime.year().month().day(), calendar: calendar)
  }

  private static func styled(_ style: Date.FormatStyle, calendar: Calendar) -> Date.FormatStyle {
    var style = style
    style.calendar = calendar
    style.timeZone = calendar.timeZone
    return style
  }
}
