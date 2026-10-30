import Testing
@testable import ImageAnalysisImpl

/// 특징 벡터 시한 차단의 앞·뒤 판정. 값 타입으로 보고 프로세스 전역(`FeaturePrinting.availability`)은 바꾸지 않는다.
struct FeaturePrintAvailabilityTests {
  @Test("지원 기기는 처음에 쓸 수 있고, 미지원 기기는 활성 여부와 관계없이 늘 못 쓴다")
  func startsBySupport() {
    var supported = FeaturePrintAvailability(isSupportedDevice: true)
    var unsupported = FeaturePrintAvailability(isSupportedDevice: false)

    #expect(supported.isAvailable)
    #expect(!unsupported.isAvailable)
    supported.appActivityChanged(isActive: false)
    unsupported.appActivityChanged(isActive: false)
    #expect(supported.isAvailable)
    #expect(!unsupported.isAvailable)
  }

  @Test("활성에서 시작해 활성에서 시한을 넘기면 앞 차단: 앞·뒤 모두, 다시 활성이 돼도 못 쓴다")
  func blocksForegroundTimeoutEverywhere() {
    var availability = FeaturePrintAvailability(isSupportedDevice: true)
    let ticket = availability.ticket()

    availability.timedOut(ticket)

    #expect(!availability.isAvailable)
    availability.appActivityChanged(isActive: false)
    #expect(!availability.isAvailable)
    availability.appActivityChanged(isActive: true)
    #expect(!availability.isAvailable)
  }

  @Test("비활성에서 시작해 시한을 넘기면 뒤 차단: 뒤에서만 못 쓰고 앞에서는 쓴다")
  func blocksBackgroundTimeoutOnlyInBackground() {
    var availability = FeaturePrintAvailability(isSupportedDevice: true)
    availability.appActivityChanged(isActive: false)
    let ticket = availability.ticket()

    availability.timedOut(ticket)

    #expect(!availability.isAvailable)
    availability.appActivityChanged(isActive: true)
    #expect(availability.isAvailable)
    availability.appActivityChanged(isActive: false)
    #expect(!availability.isAvailable)
  }

  @Test("활성에서 시작해 도중에 뒤로 갔다 돌아온 뒤 시한을 넘기면 뒤 차단이다")
  func treatsRequestThatWentBackgroundAsBackground() {
    var availability = FeaturePrintAvailability(isSupportedDevice: true)
    let ticket = availability.ticket()
    availability.appActivityChanged(isActive: false)
    availability.appActivityChanged(isActive: true)

    availability.timedOut(ticket)

    #expect(availability.isAvailable)
    availability.appActivityChanged(isActive: false)
    #expect(!availability.isAvailable)
  }

  @Test("같은 값 알림은 전이 수를 바꾸지 않는다")
  func ignoresRepeatedActivity() {
    var availability = FeaturePrintAvailability(isSupportedDevice: true)
    let ticket = availability.ticket()
    availability.appActivityChanged(isActive: true)

    availability.timedOut(ticket)

    #expect(availability.backgroundEntries == 0)
    #expect(availability.isBlockedInForeground)
  }

  @Test("뒤 차단 뒤에 앞에서 시한을 넘기면 앞 차단도 걸린다")
  func addsForegroundBlockAfterBackgroundBlock() {
    var availability = FeaturePrintAvailability(isSupportedDevice: true)
    availability.appActivityChanged(isActive: false)
    availability.timedOut(availability.ticket())
    availability.appActivityChanged(isActive: true)

    availability.timedOut(availability.ticket())

    #expect(availability.isBlockedInBackground)
    #expect(availability.isBlockedInForeground)
    #expect(!availability.isAvailable)
  }

  @Test("뒤 요청이 남은 채 앞으로 와 앞 요청이 시한을 넘기면 한 번만 뒤 차단으로 매기고, 두 번째는 앞 차단이다")
  func excusesFirstForegroundTimeoutWhileBackgroundRequestRemains() {
    var availability = FeaturePrintAvailability(isSupportedDevice: true)
    availability.appActivityChanged(isActive: false)
    let background = availability.ticket()
    availability.requestStarted(background)
    availability.appActivityChanged(isActive: true)

    availability.timedOut(availability.ticket())

    #expect(availability.isAvailable)
    #expect(availability.isBlockedInBackground)
    #expect(availability.hasExcusedForegroundTimeout)

    availability.timedOut(availability.ticket())

    #expect(!availability.isAvailable)
    #expect(availability.isBlockedInForeground)
  }

  @Test("뒤 요청이 돌아온 뒤의 앞 시한은 앞 차단이다")
  func blocksForegroundAfterBackgroundRequestEnded() {
    var availability = FeaturePrintAvailability(isSupportedDevice: true)
    availability.appActivityChanged(isActive: false)
    let background = availability.ticket()
    availability.requestStarted(background)
    availability.requestEnded(background)
    availability.appActivityChanged(isActive: true)

    availability.timedOut(availability.ticket())

    #expect(availability.backgroundRequestsInFlight == 0)
    #expect(availability.isBlockedInForeground)
    #expect(!availability.isAvailable)
  }

  @Test("앞 ticket 의 요청은 남은 뒤 요청으로 세지 않는다")
  func countsOnlyBackgroundRequests() {
    var availability = FeaturePrintAvailability(isSupportedDevice: true)
    let foreground = availability.ticket()

    availability.requestStarted(foreground)

    #expect(availability.backgroundRequestsInFlight == 0)
  }
}
