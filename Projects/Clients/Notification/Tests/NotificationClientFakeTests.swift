import Core
import NotificationInterface
import NotificationTesting
import Synchronization
import Testing

struct NotificationClientFakeTests {
  @Test("설정 열기를 센다")
  func countsOpenSettings() async {
    let fake = NotificationClientFake(authorization: .denied)

    await fake.openSettings()
    await fake.openSettings()

    #expect(fake.openSettingsCount == 2)
    #expect(fake.authorization == .denied)
  }

  @Test("권한을 요청하면 정해 둔 상태로 바뀌고 횟수를 센다")
  func changesAuthorizationAfterRequest() async {
    let fake = NotificationClientFake(authorization: .notDetermined, authorizationAfterRequest: .authorized)

    let before = await fake.authorizationStatus()
    let requested = await fake.requestAuthorization()
    let after = await fake.authorizationStatus()

    #expect(before == .notDetermined)
    #expect(requested == .authorized)
    #expect(after == .authorized)
    #expect(fake.requestAuthorizationCount == 1)
  }

  @Test("요청 뒤 상태를 정하지 않으면 그대로다")
  func keepsAuthorizationWithoutAfterRequest() async {
    let fake = NotificationClientFake(authorization: .denied)

    #expect(await fake.requestAuthorization() == .denied)
    #expect(fake.authorization == .denied)
  }

  @Test("같은 식별자로 추가하면 바꾸고, 지우면 대기에서 빠진다")
  func addsReplacesAndRemoves() async throws {
    let first = try request("a", body: "처음")
    let fake = NotificationClientFake(pending: [first])

    let replaced = try request("a", body: "바뀜")
    let other = try request("b")
    try await fake.add([replaced, other])
    await fake.removePendingRequests(ids: ["b", "missing"])

    #expect(fake.pendingRequests == [replaced])
    #expect(await fake.pendingRequestIDs() == ["a"])
    #expect(fake.addedBatches == [[replaced, other]])
    #expect(fake.removedBatches == [["b", "missing"]])
  }

  @Test("실패하는 식별자만 건너뛰고 나머지는 넣은 뒤 던진다")
  func skipsFailingIDsAndThrows() async throws {
    let fake = NotificationClientFake(failingAddIDs: ["b"])
    let requests = try [request("a"), request("b"), request("c")]

    await #expect(throws: NotificationError.failed) {
      try await fake.add(requests)
    }

    #expect(fake.pendingRequests.map(\.id) == ["a", "c"])
    #expect(fake.addedBatches.map { $0.map(\.id) } == [["a", "c"]])
    #expect(fake.addAttemptCount == 1)
  }

  @Test("권한 상태 훅은 호출 번호를 0부터 받는다")
  func passesCallIndexToAuthorizationStatusHook() async {
    let indexes = Mutex<[Int]>([])
    let fake = NotificationClientFake(onAuthorizationStatus: { index in indexes.withLock { $0.append(index) } })

    _ = await fake.authorizationStatus()
    _ = await fake.authorizationStatus()
    _ = await fake.authorizationStatus()

    #expect(indexes.withLock { $0 } == [0, 1, 2])
  }

  @Test("권한 상태는 훅을 기다리기 전에 읽은 값을 돌려준다")
  func returnsStatusReadBeforeHook() async {
    let fake = Later<NotificationClientFake>()
    let instance = NotificationClientFake(
      authorization: .notDetermined,
      authorizationAfterRequest: .authorized,
      onAuthorizationStatus: { index in
        if index == 0 {
          _ = await fake.value?.requestAuthorization()
        }
      }
    )
    fake.set(instance)

    #expect(await instance.authorizationStatus() == .notDetermined)
    #expect(instance.authorization == .authorized)
  }

  @Test("대기 조회 훅은 호출 번호를 0부터 받고, 기다리는 동안 바뀐 대기가 아니라 훅 전에 읽은 식별자를 돌려준다")
  func returnsPendingIDsReadBeforeHook() async throws {
    let indexes = Mutex<[Int]>([])
    let fake = Later<NotificationClientFake>()
    let added = try request("b")
    let instance = try NotificationClientFake(
      pending: [request("a")],
      onPendingRequestIDs: { index in
        indexes.withLock { $0.append(index) }
        if index == 0 {
          try? await fake.value?.add([added])
        }
      }
    )
    fake.set(instance)

    let first = await instance.pendingRequestIDs()
    let second = await instance.pendingRequestIDs()

    #expect(first == ["a"])
    #expect(second == ["a", "b"])
    #expect(indexes.withLock { $0 } == [0, 1])
  }

  @Test("권한 요청 훅은 상태를 바꾸기 전에 부른다")
  func callsRequestHookBeforeChangingStatus() async {
    let observed = Mutex<NotificationAuthorization?>(nil)
    let fake = Later<NotificationClientFake>()
    let instance = NotificationClientFake(
      authorization: .notDetermined,
      authorizationAfterRequest: .authorized,
      onRequestAuthorization: {
        let current = fake.value?.authorization
        observed.withLock { $0 = current }
      }
    )
    fake.set(instance)

    _ = await instance.requestAuthorization()

    #expect(observed.withLock { $0 } == .notDetermined)
  }
}

/// 훅이 만들기 전의 대역을 참조하도록 나중에 채운다.
private final class Later<Value: Sendable>: Sendable {
  private let storage = Mutex<Value?>(nil)

  var value: Value? {
    self.storage.withLock { $0 }
  }

  func set(_ value: Value) {
    self.storage.withLock { $0 = value }
  }
}

private func request(_ id: String, body: String = "본문") throws -> NotificationRequest {
  try NotificationRequest(
    id: id,
    title: "제목",
    body: body,
    date: #require(LocalDate(year: 2026, month: 12, day: 24)),
    hour: 9,
    minute: 0
  )
}
