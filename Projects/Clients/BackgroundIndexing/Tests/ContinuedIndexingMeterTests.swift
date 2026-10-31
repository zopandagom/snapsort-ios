import BackgroundIndexingInterface
import IndexingInterface
import Testing
import TripPlaceInterface
@testable import BackgroundIndexingImpl

/// 계속 처리 작업의 시스템 진행 표시 계산 (설계 §5.1, R1-2·R1-3, R2-3). 개수 규칙은 단위 무게(`.unit`)로 본다.
/// 가중 단위·예약은 ContinuedIndexingMeterWeightTests.
struct ContinuedIndexingMeterTests {
  @Test("첫 값이 끝이면 바로 끝이고 바꿀 문구가 없다")
  func finishedAtFirst() {
    var meter = ContinuedIndexingMeter(weights: .unit)

    meter.receive(IndexingProgress(totalCount: 3, indexedCount: 3, skippedCount: 0))

    #expect(meter.isFinished)
    #expect(meter.status == nil)
    #expect(meter.completed == 0)
  }

  @Test("1단계는 분류한 만큼 완료가 오르고, 대기가 늘면 전체만 는다")
  func classifying() {
    var meter = ContinuedIndexingMeter(weights: .unit)

    meter.receive(IndexingProgress(totalCount: 10, indexedCount: 2, skippedCount: 0))
    #expect((meter.completed, meter.total) == (0, 8))
    #expect(meter.status == ContinuedIndexingStatus(stage: .classifying, doneCount: 2, totalCount: 10))

    meter.receive(IndexingProgress(totalCount: 10, indexedCount: 5, skippedCount: 1, pendingTextCount: 4))
    #expect((meter.completed, meter.total) == (4, 12))
    #expect(meter.status == ContinuedIndexingStatus(stage: .classifying, doneCount: 6, totalCount: 10))
  }

  @Test("2단계는 글자를 읽은 만큼 완료가 오르고 수는 보관함 진행 카드와 같다")
  func recognizingText() {
    var meter = ContinuedIndexingMeter(weights: .unit)

    meter.receive(IndexingProgress(totalCount: 10, indexedCount: 10, skippedCount: 0, pendingTextCount: 5))
    meter.receive(IndexingProgress(
      totalCount: 10,
      indexedCount: 10,
      skippedCount: 0,
      pendingTextCount: 3,
      recognizedTextCount: 1,
      skippedTextCount: 1
    ))

    #expect((meter.completed, meter.total) == (2, 5))
    #expect(meter.status == ContinuedIndexingStatus(stage: .recognizingText, doneCount: 2, totalCount: 5))
  }

  @Test("계속 처리 중 새 사진이 오면 남은 수가 늘어도 완료는 줄지 않고, 그 사진을 분류하는 동안에도 오른다")
  func newPhotosKeepCounting() {
    var meter = ContinuedIndexingMeter(weights: .unit)

    meter.receive(IndexingProgress(totalCount: 10, indexedCount: 8, skippedCount: 0))
    meter.receive(IndexingProgress(totalCount: 10, indexedCount: 10, skippedCount: 0))
    #expect(meter.completed == 2)
    meter.receive(IndexingProgress(totalCount: 13, indexedCount: 10, skippedCount: 0))
    #expect((meter.completed, meter.total) == (2, 5))
    meter.receive(IndexingProgress(totalCount: 13, indexedCount: 12, skippedCount: 0))

    #expect((meter.completed, meter.total) == (4, 5))
  }

  @Test("재시작으로 건너뜀이 풀려 남은 수가 늘어도 완료는 줄지 않는다")
  func restartUnskipsWithoutGoingBack() {
    var meter = ContinuedIndexingMeter(weights: .unit)

    meter.receive(IndexingProgress(totalCount: 10, indexedCount: 6, skippedCount: 2))
    meter.receive(IndexingProgress(totalCount: 10, indexedCount: 7, skippedCount: 3))
    #expect(meter.completed == 2)
    meter.runRestarted()
    meter.receive(IndexingProgress(totalCount: 10, indexedCount: 7, skippedCount: 0))

    #expect(meter.completed == 2)
    #expect(meter.total >= 5)
  }

  @Test("재시작 표시 없이 글자 처리 수가 줄면 순서가 뒤바뀐 옛 값으로 보고 버린다")
  func ignoresOutOfOrderTextDecrease() {
    var meter = ContinuedIndexingMeter(weights: .unit)

    // 첫 값의 처리 수는 작업 전에 한 것이라 기준으로만 쓴다.
    meter.receive(Self.text(done: 4, pending: 6))
    meter.receive(Self.text(done: 2, pending: 8))
    #expect(meter.completed == 0)
    meter.receive(Self.text(done: 5, pending: 5))

    #expect(meter.completed == 1)
  }

  @Test("재시작 표시 뒤 처음 온 글자 처리 수 감소는 새 실행으로 0 부터 더한다")
  func countsTextAfterRestart() {
    var meter = ContinuedIndexingMeter(weights: .unit)

    meter.receive(Self.text(done: 4, pending: 6))
    meter.runRestarted()
    meter.receive(Self.text(done: 1, pending: 5))
    #expect(meter.completed == 1)
    meter.receive(Self.text(done: 3, pending: 3))

    #expect(meter.completed == 3)
  }

  // 라운드 7(R7-2.4): 전체는 완료 + 남은 추정이라 추정이 줄면 준다. 그래서 "전체도 줄지 않는다" 대신 "완료 아래로 내려가지 않는다"를 본다.
  @Test("완료는 줄지 않고 전체는 완료 아래로 내려가지 않는다")
  func completedNeverDecreases() {
    var meter = ContinuedIndexingMeter(weights: .unit)
    let values = [
      IndexingProgress(totalCount: 10, indexedCount: 2, skippedCount: 0),
      IndexingProgress(totalCount: 8, indexedCount: 4, skippedCount: 0),
      IndexingProgress(totalCount: 8, indexedCount: 8, skippedCount: 0, pendingTextCount: 2),
      IndexingProgress(totalCount: 8, indexedCount: 8, skippedCount: 0, pendingTextCount: 1, recognizedTextCount: 1),
    ]
    var previous: Int64 = 0

    for value in values {
      meter.receive(value)
      #expect(meter.completed >= previous)
      #expect(meter.completed <= meter.total)
      #expect(meter.total >= 1)
      previous = meter.completed
    }
  }

  @Test("hold 를 놓은 뒤에는 분류 남은 수·글자 대기를 막대에 넣지 않고 그 뒤 분류 진행률은 버린다")
  func ignoresIndexingAfterEnd() {
    var meter = ContinuedIndexingMeter(weights: .unit)

    meter.receive(IndexingProgress(totalCount: 10, indexedCount: 10, skippedCount: 0, pendingTextCount: 2))
    meter.receive(IndexingProgress(totalCount: 10, indexedCount: 10, skippedCount: 0, recognizedTextCount: 2))
    meter.indexingEnded()
    meter.receive(IndexingProgress(totalCount: 20, indexedCount: 10, skippedCount: 0))

    #expect((meter.completed, meter.total) == (2, 2))
    #expect(meter.status == nil)
  }

  @Test("장소 키를 단위로 더하고, 끝 뒤 회차가 도는 동안만 장소 단계다")
  func placeUnits() {
    var meter = ContinuedIndexingMeter(weights: .unit)
    meter.receive(IndexingProgress(totalCount: 10, indexedCount: 10, skippedCount: 0, pendingTextCount: 2))

    meter.placeRoundStarted()
    meter.placeProgress(TripPlacePrefetchProgress(doneCount: 0, totalCount: 3))
    #expect(meter.status?.stage == .recognizingText)
    #expect((meter.completed, meter.total) == (0, 5))

    meter.receive(IndexingProgress(totalCount: 10, indexedCount: 10, skippedCount: 0, recognizedTextCount: 2))
    meter.indexingEnded()
    meter.placeProgress(TripPlacePrefetchProgress(doneCount: 1, totalCount: 3))

    #expect(meter.status == ContinuedIndexingStatus(stage: .fetchingPlaceNames, doneCount: 1, totalCount: 3))
    #expect((meter.completed, meter.total) == (3, 5))
  }

  @Test("회차 끝에 못 한 키를 전체에서 빼고, 두 회차의 처리 키를 쌓는다")
  func placeRounds() {
    var meter = ContinuedIndexingMeter(weights: .unit)
    meter.receive(IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0))
    meter.indexingEnded()

    meter.placeRoundStarted()
    #expect(meter.status == ContinuedIndexingStatus(stage: .fetchingPlaceNames, doneCount: 0, totalCount: 0))
    meter.placeProgress(TripPlacePrefetchProgress(doneCount: 0, totalCount: 4))
    meter.placeProgress(TripPlacePrefetchProgress(doneCount: 1, totalCount: 4))
    meter.placeRoundEnded()
    #expect((meter.completed, meter.total) == (1, 1))
    #expect(meter.status == nil)

    meter.placeRoundStarted()
    meter.placeProgress(TripPlacePrefetchProgress(doneCount: 0, totalCount: 2))
    meter.placeProgress(TripPlacePrefetchProgress(doneCount: 2, totalCount: 2))
    meter.placeRoundEnded()

    #expect((meter.completed, meter.total) == (3, 3))
    #expect(meter.placeDone == 3)
    #expect(meter.endedRounds == 2)
  }

  private static func text(done: Int, pending: Int) -> IndexingProgress {
    IndexingProgress(
      totalCount: 10,
      indexedCount: 10,
      skippedCount: 0,
      pendingTextCount: pending,
      recognizedTextCount: done
    )
  }
}
