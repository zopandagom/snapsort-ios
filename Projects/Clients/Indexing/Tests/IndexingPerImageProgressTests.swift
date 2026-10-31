import Core
import Foundation
import IndexingInterface
import Synchronization
import Testing
@testable import IndexingImpl

/// 2단계 배치 안 장마다의 저장 전 진행률 (docs/ARCHITECTURE.md §4 인덱싱): BG hold 에만 가고, 앞 구독자·최신 값·보관 값에는 들어가지 않으며,
/// 끝 값이 아니고, 읽은 장은 저장과 같은 조건으로 센다. 계속 처리 작업이 글자 읽기 단계에서도 고르게 진행을 보이게 한다.
@Suite(.timeLimit(.minutes(1)))
struct IndexingExecutorPerImageProgressTests {
  @Test("2단계에서 hold 는 배치 안 장마다 값을 받고, 앞 구독자는 저장 뒤 배치 값만 받는다")
  func holdGetsPerImageProgress() async {
    let turns = RecognizeTurns(gated: [0])
    let fixture = Fixture(library: newestFirstPhotos, onRecognize: { _ in await turns.enter() }, textBatchSize: 3)
    let indexing = fixture.indexing
    let consumer = ProgressConsumer(indexing)
    await turns.waitForCall(0)
    let hold = Arrivals()

    let task = Task { await indexing.runInBackground(shouldYield: { false }, progress: { hold.receive($0) }) }
    await hold.waitForValue()
    turns.open(0)
    _ = await task.value
    await consumer.waitUntilFinished()

    // 붙을 때 받은 1단계 값(0) 뒤 장마다 1·2, 저장 뒤 배치 값 3.
    #expect(hold.values.all.map(\.recognizedTextCount).removingRepeats() == [0, 1, 2, 3])
    #expect(consumer.received.allSatisfy { [0, 3].contains($0.recognizedTextCount) })
    #expect(consumer.received.last?.recognizedTextCount == 3)
    consumer.cancel()
  }

  @Test("장마다 값은 최신 값을 바꾸지 않아, 배치 도중 새로 붙는 hold 는 저장된 값을 먼저 받는다")
  func perImageProgressLeavesLatest() async {
    let turns = RecognizeTurns(gated: [0, 1])
    let fixture = Fixture(library: newestFirstPhotos, onRecognize: { _ in await turns.enter() }, textBatchSize: 3)
    let indexing = fixture.indexing
    let consumer = ProgressConsumer(indexing)
    await turns.waitForCall(0)
    let first = Arrivals()
    let firstTask = Task { await indexing.runInBackground(shouldYield: { false }, progress: { first.receive($0) }) }
    await first.waitForValue()
    turns.open(0)
    // 둘째 장에 들어왔으면 첫 장의 장마다 값은 이미 첫 hold 에 닿았다(같은 실행 Task 에서 차례로 보낸다).
    await turns.waitForCall(1)
    #expect(first.values.all.last?.recognizedTextCount == 1)

    let second = Arrivals()
    let secondTask = Task { await indexing.runInBackground(shouldYield: { false }, progress: { second.receive($0) }) }
    await second.waitForValue()

    #expect(second.values.all.first?.recognizedTextCount == 0)
    #expect(second.values.all.first?.pendingTextCount == 3)
    turns.open(1)
    _ = await firstTask.value
    _ = await secondTask.value
    consumer.cancel()
  }

  @Test("비활성 중 장마다 값은 보관 값에 들어가지 않아, 앞으로 올 때 앞 구독자는 저장된 값을 받는다")
  func perImageProgressNotHeldWhileInactive() async {
    let turns = RecognizeTurns(gated: [1, 2])
    let fixture = Fixture(library: newestFirstPhotos, onRecognize: { _ in await turns.enter() }, textBatchSize: 3)
    let indexing = fixture.indexing
    indexing.appActivityChanged(isActive: false)
    let front = Arrivals()
    let consumer = Task {
      for await progress in indexing.run() {
        front.receive(progress)
      }
    }
    let hold = Arrivals()
    let task = Task { await indexing.runInBackground(shouldYield: { false }, progress: { hold.receive($0) }) }
    await turns.waitForCall(1)
    #expect(hold.values.all.last?.recognizedTextCount == 1)
    #expect(front.values.all.isEmpty)

    // 앞으로 오면 뒤 실행은 멈추고(묶인 OCR 은 취소로 풀린다) 새 실행이 2단계에 들어와 셋째 호출에서 묶인다.
    indexing.appActivityChanged(isActive: true)
    await turns.waitForCall(2)
    await front.waitForValue()

    #expect(front.values.all.first?.recognizedTextCount == 0)
    #expect(front.values.all.allSatisfy { $0.recognizedTextCount == 0 })
    turns.open(2)
    _ = await task.value
    consumer.cancel()
  }
}

/// 실행 하나를 끝까지 돌려 장마다 값(`RunEnvironment.reportToHolds`)과 배치 값(`report`)의 차례를 본다.
@Suite(.timeLimit(.minutes(1)))
struct IndexingRunPerImageProgressTests {
  @Test("장마다 값은 저장 전 읽은 장만큼 읽은 수가 크고 대기가 작으며, 미룬 장은 저장과 같이 세지 않는다")
  func perImageCounts() async {
    let fixture = Fixture(library: newestFirstPhotos, recognizeFailures: ["b"], textBatchSize: 3)

    let (sent, _) = await recordRun(fixture)

    // "a" 읽음 → "b" 읽지 못해 미룸 → "c" 읽음(마지막 장 뒤는 보내지 않음) → 저장 뒤 배치 값.
    let perImage = sent.compactMap(\.perImage)
    #expect(perImage.map(\.recognizedTextCount) == [1, 1])
    #expect(perImage.map(\.pendingTextCount) == [2, 1])
    #expect(perImage.map(\.skippedTextCount) == [0, 1])
    let saved = sent.compactMap(\.batch).last
    #expect(saved?.recognizedTextCount == 2)
    #expect(saved?.skippedTextCount == 1)
    // 장마다 값의 읽은 수는 저장한 장 수를 넘지 않는다(저장과 같은 거르기).
    #expect(perImage.allSatisfy { $0.recognizedTextCount <= saved?.recognizedTextCount ?? 0 })
  }

  @Test("장마다 값은 끝이 아니고, 끝 값은 그 뒤 저장한 배치 값에서만 온다")
  func perImageProgressIsNeverFinished() async {
    let fixture = Fixture(library: newestFirstPhotos, textBatchSize: 3)

    let (sent, _) = await recordRun(fixture)

    let perImage = sent.compactMap(\.perImage)
    #expect(perImage.count == 2)
    #expect(perImage.allSatisfy { $0.phase == .recognizingText })
    let lastPerImage = sent.lastIndex { $0.perImage != nil }
    let firstFinished = sent.firstIndex { ($0.perImage ?? $0.batch)?.isFinished == true }
    #expect(lastPerImage.map { $0 + 1 } == firstFinished)
    #expect(firstFinished.flatMap { sent[$0].batch }?.recognizedTextCount == 3)
  }

  @Test("2단계 배치가 한 장이면 장마다 값이 없다")
  func noPerImageProgressForSingleImageBatch() async {
    let fixture = Fixture(library: newestFirstPhotos, textBatchSize: 1)

    let (sent, _) = await recordRun(fixture)

    #expect(sent.compactMap(\.perImage).isEmpty)
    #expect(sent.compactMap(\.batch).last?.recognizedTextCount == 3)
  }

  @Test("BG 모드에서 Vision 이 잇달아 실패해 배치 도중 멈추면 멈춘 장 뒤에는 장마다 값이 없고 저장 뒤 배치 값을 한 번 보낸다")
  func visionStopSendsNoPerImageAfterStop() async {
    let photos = newestFirstPhotos + [.stub(id: "d", creationDate: date(month: 5, day: 0))]
    let fixture = Fixture(library: photos, recognizeFailures: ["a", "b", "c", "d"], textBatchSize: 4)

    let (sent, end) = await recordRun(fixture, isBackground: true)

    #expect(end == .visionStopped)
    // 1·2번째 실패 뒤 장마다 값, 3번째 실패에서 멈춰 그 뒤 배치 값으로 끝난다("d" 는 대기로 남는다).
    let phaseTwo = sent.drop { $0.perImage == nil }
    #expect(phaseTwo.map(\.perImage?.skippedTextCount) == [1, 2, nil])
    #expect(phaseTwo.last?.batch?.skippedTextCount == 3)
    #expect(phaseTwo.last?.batch?.pendingTextCount == 1)
  }
}

// MARK: - 준비

/// 최신순(2단계 읽는 차례)으로 "a", "b", "c". 기본 라벨이라 모두 OCR 대상이다.
private let newestFirstPhotos: [ImageAsset] = ["a", "b", "c"].enumerated().map { index, id in
  .stub(id: id, creationDate: date(month: 5, day: 3 - index))
}

/// 실행이 보낸 진행률 하나와 그 경로.
private enum Sent: Sendable {
  /// 2단계 배치 안 장마다(hold 에만).
  case perImage(IndexingProgress)
  /// `report` 로 보낸 저장 뒤 값.
  case batch(IndexingProgress)

  var perImage: IndexingProgress? {
    if case let .perImage(progress) = self {
      progress
    } else {
      nil
    }
  }

  var batch: IndexingProgress? {
    if case let .batch(progress) = self {
      progress
    } else {
      nil
    }
  }
}

/// 변경 스트림을 끝내고 실행 하나를 끝까지 돌려, 보낸 진행률을 보낸 차례대로 돌려준다.
private func recordRun(_ fixture: Fixture, isBackground: Bool = false) async -> ([Sent], IndexingRunEnd) {
  fixture.photoLibrary.finishImageChanges()
  let sent = Received<Sent>()
  var run = fixture.indexing.makeRun(environment: RunEnvironment(
    isBackground: { isBackground },
    reportToHolds: { sent.append(.perImage($0)) }
  ))
  let end = await run.start { sent.append(.batch($0)) }
  return (sent.all, end)
}

/// 다른 Task 에서 받은 진행률을 모으고, 받을 때마다 알린다. 폴링 없이 "값이 왔다"를 기다린다(한 번에 한 Task 만 기다린다).
private final class Arrivals: Sendable {
  let values = Received<IndexingProgress>()
  private let arrivals: AsyncStream<Void>
  private let arrived: AsyncStream<Void>.Continuation

  init() {
    (self.arrivals, self.arrived) = AsyncStream.makeStream(of: Void.self)
  }

  func receive(_ progress: IndexingProgress) {
    self.values.append(progress)
    self.arrived.yield()
  }

  /// 아직 기다리지 않은 다음 값 하나가 올 때까지 기다린다(이미 왔으면 바로 돌아온다).
  func waitForValue() async {
    for await _ in self.arrivals {
      return
    }
  }
}

/// OCR 대역의 차례. 호출마다 들어옴을 알리고, 정한 호출은 테스트가 열 때까지(또는 Task 가 취소될 때까지) 기다린다. 폴링하지 않는다.
private final class RecognizeTurns: Sendable {
  private let calls = Mutex(0)
  private let entries: AsyncStream<Int>
  private let entered: AsyncStream<Int>.Continuation
  private let gates: [Int: Opening]

  init(gated: Set<Int>) {
    (self.entries, self.entered) = AsyncStream.makeStream(of: Int.self)
    self.gates = Dictionary(uniqueKeysWithValues: gated.map { ($0, Opening()) })
  }

  /// OCR 대역이 호출마다 부른다.
  func enter() async {
    let call = self.calls.withLock { value in
      defer { value += 1 }
      return value
    }
    self.entered.yield(call)
    await self.gates[call]?.wait()
  }

  /// `call` 번째(0부터) 호출이 들어올 때까지 기다린다.
  func waitForCall(_ call: Int) async {
    for await entry in self.entries where entry >= call {
      return
    }
  }

  func open(_ call: Int) {
    self.gates[call]?.open()
  }
}

/// 한 번 열면 기다림이 끝나는 문. 기다리는 Task 가 취소돼도 끝난다(멈춘 실행의 OCR 이 풀린다).
private final class Opening: Sendable {
  private let stream: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation

  init() {
    (self.stream, self.continuation) = AsyncStream.makeStream(of: Void.self)
  }

  func open() {
    self.continuation.finish()
  }

  func wait() async {
    for await _ in self.stream {}
  }
}

private extension Array where Element: Equatable {
  /// 잇달아 같은 값을 하나로 줄인다.
  func removingRepeats() -> [Element] {
    self.reduce(into: []) { result, value in
      if result.last != value {
        result.append(value)
      }
    }
  }
}
