/// 특징 벡터를 쓸 수 있는지의 앞·뒤 시한 차단 (docs/ARCHITECTURE.md §4 정리 도우미).
/// 앱이 앞에 있는 동안 요청이 시한을 넘기면 앞 차단(프로세스 끝까지 앞·뒤 모두 못 씀), 그 밖(뒤에서 시작했거나 요청 도중 뒤로 간 적 있음)은
/// 뒤 차단(프로세스 끝까지 앱이 뒤에 있을 때만 못 씀)이다. 백그라운드는 GPU 제약·낮은 우선순위로 원인이 달라 뒤의 시한을 앞의 판정 근거로 쓰지 않는다.
/// 뒤에서 시작한 요청이 아직 돌아오지 않은 동안 앞 요청이 그 뒤에 줄 서 시한을 넘기면, 한 번만 뒤 차단으로 매긴다(앞 면제).
/// 순수 값 타입이라 테스트가 프로세스 전역(`FeaturePrinting.availability`)을 바꾸지 않고 판정을 본다.
struct FeaturePrintAvailability: Sendable, Equatable {
  /// 요청을 시작할 때의 상태. 시한 판정에 쓴다.
  struct Ticket: Sendable, Equatable {
    let isAppActive: Bool
    let backgroundEntries: Int
  }

  let isSupportedDevice: Bool
  private(set) var isAppActive = true
  /// 활성 → 비활성 전이 수. 요청 도중 뒤로 간 적이 있는지 가린다.
  private(set) var backgroundEntries = 0
  private(set) var isBlockedInForeground = false
  private(set) var isBlockedInBackground = false
  /// 뒤 ticket 으로 시작해 Vision 작업이 아직 돌아오지 않은 요청 수.
  private(set) var backgroundRequestsInFlight = 0
  /// 앞 면제(뒤 요청이 남은 동안의 앞 시한을 뒤 차단으로 매김)를 이미 썼는지. 프로세스에 한 번이다.
  private(set) var hasExcusedForegroundTimeout = false

  /// 지금 쓸 수 있는지.
  var isAvailable: Bool {
    self.isSupportedDevice && !self.isBlockedInForeground && (self.isAppActive || !self.isBlockedInBackground)
  }

  /// 같은 값이면 그대로 둔다. 활성 → 비활성이면 전이 수를 하나 늘린다.
  mutating func appActivityChanged(isActive: Bool) {
    guard isActive != self.isAppActive else { return }
    self.isAppActive = isActive
    if !isActive {
      self.backgroundEntries += 1
    }
  }

  /// 요청을 시작할 때 부른다.
  func ticket() -> Ticket {
    Ticket(isAppActive: self.isAppActive, backgroundEntries: self.backgroundEntries)
  }

  /// Vision 작업을 시작했다. 뒤 ticket 이면 남은 뒤 요청으로 센다.
  mutating func requestStarted(_ ticket: Ticket) {
    if !ticket.isAppActive {
      self.backgroundRequestsInFlight += 1
    }
  }

  /// Vision 작업이 끝났다(성공·실패·취소 뒤 늦게 돌아온 것 포함).
  mutating func requestEnded(_ ticket: Ticket) {
    if !ticket.isAppActive {
      self.backgroundRequestsInFlight = max(self.backgroundRequestsInFlight - 1, 0)
    }
  }

  /// 요청이 시한을 넘겼다. 시작·지금 모두 활성이고 그 사이 뒤로 간 적이 없으면 앞 판정, 아니면 뒤 차단이다.
  /// 앞 판정이어도 뒤 요청이 남아 있고 면제를 아직 안 썼으면 한 번만 뒤 차단으로 매긴다.
  mutating func timedOut(_ ticket: Ticket) {
    let isForeground = ticket.isAppActive && self.isAppActive && ticket.backgroundEntries == self.backgroundEntries
    guard isForeground else {
      self.isBlockedInBackground = true
      return
    }
    if self.backgroundRequestsInFlight > 0, !self.hasExcusedForegroundTimeout {
      self.hasExcusedForegroundTimeout = true
      self.isBlockedInBackground = true
      return
    }
    self.isBlockedInForeground = true
  }
}
