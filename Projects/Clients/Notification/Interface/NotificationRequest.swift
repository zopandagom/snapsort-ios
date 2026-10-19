import Core

/// 날짜와 시각으로 한 번 울리는 로컬 알림 요청.
public struct NotificationRequest: Sendable, Hashable, Identifiable {
  /// 같은 식별자로 다시 추가하면 시스템이 바꾼다. 내용이 다르면 식별자도 달라지게 짓는다(부르는 쪽 책임).
  public let id: String
  public let title: String
  public let body: String
  /// 울리는 날. 시간대 없는 날짜이고, 기기 시간대의 `hour`:`minute` 에 울린다(시간대를 바꾸면 그곳의 그 시각).
  public let date: LocalDate
  public let hour: Int
  public let minute: Int

  public init(id: String, title: String, body: String, date: LocalDate, hour: Int, minute: Int) {
    self.id = id
    self.title = title
    self.body = body
    self.date = date
    self.hour = hour
    self.minute = minute
  }
}
