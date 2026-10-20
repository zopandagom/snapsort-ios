import ClassifierInterface
import ClassifierTesting
import Core
import Testing

struct ClassifierClientFakeTests {
  private let lines = [RecognizedTextLine.line("GS25"), .line("유효기간 2026.12.31")]

  @Test("정해 둔 답을 돌려주고 요청을 기록한다")
  func returnsConfiguredAnswersAndRecordsRequests() async throws {
    let answer = GifticonModelAnswer(expiryText: "2026.12.31", redemptionPlace: "GS25")
    let fake = ClassifierClientFake(
      classifyResult: .success([.receipt, .food, .other]),
      extractResult: .success(answer)
    )

    // 실제 구현처럼 정보형만 남긴다.
    #expect(try await fake.classify(self.lines) == [.receipt])
    #expect(try await fake.extractGifticon(from: self.lines) == answer)
    // 줄이 없으면 모델까지 가지 않는다.
    #expect(try await fake.classify([]).isEmpty)

    #expect(fake.requests == [.classify(self.lines), .extractGifticon(self.lines)])
  }

  @Test("모델을 쓸 수 없으면 unavailable 을 던진다")
  func throwsUnavailableWhenModelUnavailable() async {
    let fake = ClassifierClientFake(isModelAvailable: false, classifyResult: .success([.receipt]))

    #expect(!fake.isModelAvailable())
    await #expect(throws: ClassifierError.unavailable) {
      try await fake.classify(self.lines)
    }
    await #expect(throws: ClassifierError.unavailable) {
      try await fake.extractGifticon(from: self.lines)
    }
    #expect(fake.requests.isEmpty)
  }

  @Test("취소된 Task 에는 cancelled 를 던진다")
  func throwsCancelledWhenTaskCancelled() async {
    let fake = ClassifierClientFake(classifyResult: .success([.receipt]))
    let lines = self.lines

    // 시작 전에 취소됐으면 모델까지 가지 않는다.
    let cancelledBefore = Task { () async -> [ClassifierError?] in
      withUnsafeCurrentTask { $0?.cancel() }
      return await [
        Self.error { () async throws(ClassifierError) in _ = try await fake.classify(lines) },
        Self.error { () async throws(ClassifierError) in _ = try await fake.extractGifticon(from: lines) },
      ]
    }
    #expect(await cancelledBefore.value == [.cancelled, .cancelled])
    #expect(fake.requests.isEmpty)

    // 답을 기다리는 동안 취소되면 답 대신 취소를 던진다.
    let startedSignals = AsyncStream.makeStream(of: Void.self)
    let waitingFake = ClassifierClientFake(
      classify: { _ in
        startedSignals.continuation.yield()
        try? await Task.sleep(for: .seconds(60))
        return .success([.receipt])
      },
      extractGifticon: { _ in
        startedSignals.continuation.yield()
        try? await Task.sleep(for: .seconds(60))
        return .success(GifticonModelAnswer(expiryText: "2026.12.31", redemptionPlace: nil))
      }
    )
    var started = startedSignals.stream.makeAsyncIterator()
    for isClassify in [true, false] {
      let task = Task { () async -> ClassifierError? in
        await Self.error { () async throws(ClassifierError) in
          if isClassify {
            _ = try await waitingFake.classify(lines)
          } else {
            _ = try await waitingFake.extractGifticon(from: lines)
          }
        }
      }
      await started.next()
      task.cancel()

      #expect(await task.value == .cancelled, "classify: \(isClassify)")
    }
  }

  @Test("쓸 수 있음 여부를 실행 중에 바꾼다")
  func changesAvailabilityWhileRunning() async throws {
    let fake = ClassifierClientFake(classifyResult: .success([.receipt]))

    fake.setModelAvailable(false)
    #expect(!fake.isModelAvailable())
    await #expect(throws: ClassifierError.unavailable) {
      try await fake.classify(self.lines)
    }

    fake.setModelAvailable(true)
    #expect(fake.isModelAvailable())
    #expect(try await fake.classify(self.lines) == [.receipt])
    #expect(fake.requests == [.classify(self.lines)])
  }

  private static func error(_ operation: () async throws(ClassifierError) -> Void) async -> ClassifierError? {
    do throws(ClassifierError) {
      try await operation()
      return nil
    } catch {
      return error
    }
  }
}
