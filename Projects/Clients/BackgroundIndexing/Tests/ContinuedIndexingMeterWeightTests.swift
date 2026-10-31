import BackgroundIndexingInterface
import IndexingInterface
import Testing
import TripPlaceInterface
@testable import BackgroundIndexingImpl

/// 계속 처리 진행 표시의 가중 단위·글자 비율 예약·장소 회차 예약·전체 규칙 (설계 R7-2, R7 반영 1). 무게는 `.default`(16·200·350, 0.2·100, 30).
struct ContinuedIndexingMeterWeightTests {
  @Test("분류 1장·글자 1장·장소 키 1개를 무게만큼 더한다")
  func weightedUnits() {
    var classify = ContinuedIndexingMeter()
    classify.receive(IndexingProgress(totalCount: 100, indexedCount: 0, skippedCount: 0))
    classify.receive(IndexingProgress(totalCount: 100, indexedCount: 50, skippedCount: 0))
    #expect(classify.completed == 800)

    var text = ContinuedIndexingMeter()
    text.receive(Self.text(done: 0, pending: 2))
    text.receive(Self.text(done: 1, pending: 1))
    #expect(text.completed == 200)

    var place = ContinuedIndexingMeter()
    place.receive(IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0))
    place.indexingEnded()
    place.placeRoundStarted()
    place.placeProgress(TripPlacePrefetchProgress(doneCount: 0, totalCount: 1))
    place.placeProgress(TripPlacePrefetchProgress(doneCount: 1, totalCount: 1))
    #expect(place.completed == 350)
  }

  @Test("아직 분류하지 않은 장에 글자 읽기 몫을 사전 비율만큼 미리 넣는다")
  func reservesTextForUnclassified() {
    var meter = ContinuedIndexingMeter()

    meter.receive(IndexingProgress(totalCount: 1000, indexedCount: 0, skippedCount: 0))

    // 1000 × (16 + 0.2 × 200)
    #expect((meter.completed, meter.total) == (0, 56000))
  }

  @Test("분류하는 동안 본 글자 대기 비율로 추정을 고치고, 추정이 줄면 완료는 그대로 전체만 준다")
  func adaptsTextShare() {
    var meter = ContinuedIndexingMeter()
    meter.receive(IndexingProgress(totalCount: 1000, indexedCount: 0, skippedCount: 0))

    meter.receive(IndexingProgress(totalCount: 1000, indexedCount: 500, skippedCount: 0, pendingTextCount: 10))

    // 비율 = (10 + 0.2 × 100) ÷ (500 + 100) = 0.05. 남은 500장 × (16 + 0.05 × 200) = 13,000, 대기 10장 × 200 = 2,000.
    #expect(abs(meter.textShare - 0.05) < 1e-9)
    #expect((meter.completed, meter.total) == (8000, 23000))
  }

  @Test("글자 비율 추정이 실제와 같으면 1단계에서 2단계로 넘어가도 전체가 바뀌지 않고, 글자 1장마다 200 씩 오른다")
  func stageChangeKeepsTotal() {
    var meter = ContinuedIndexingMeter()

    meter.receive(IndexingProgress(totalCount: 100, indexedCount: 0, skippedCount: 0))
    #expect((meter.completed, meter.total) == (0, 5600))
    meter.receive(IndexingProgress(totalCount: 100, indexedCount: 50, skippedCount: 0, pendingTextCount: 10))
    #expect((meter.completed, meter.total) == (800, 5600))
    #expect(meter.status?.stage == .classifying)
    meter.receive(IndexingProgress(totalCount: 100, indexedCount: 100, skippedCount: 0, pendingTextCount: 20))
    #expect((meter.completed, meter.total) == (1600, 5600))
    #expect(meter.status?.stage == .recognizingText)
    meter.receive(IndexingProgress(
      totalCount: 100,
      indexedCount: 100,
      skippedCount: 0,
      pendingTextCount: 19,
      recognizedTextCount: 1
    ))

    #expect((meter.completed, meter.total) == (1800, 5600))
  }

  @Test("회차가 돌 수 있으면 회차 키 상한만큼 미리 넣고, 회차가 키 수를 알리면 전체가 늘지 않고 준다")
  func reservesPlaceRound() {
    var meter = ContinuedIndexingMeter(reservesPlaceRound: true)
    meter.receive(IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0))
    meter.indexingEnded()
    // 30 × 350
    #expect((meter.completed, meter.total) == (0, 10500))

    meter.placeRoundStarted()
    #expect((meter.completed, meter.total) == (0, 10500))
    meter.placeProgress(TripPlacePrefetchProgress(doneCount: 0, totalCount: 3))
    #expect((meter.completed, meter.total) == (0, 1050))
    meter.placeProgress(TripPlacePrefetchProgress(doneCount: 1, totalCount: 3))
    #expect((meter.completed, meter.total) == (350, 1050))
    meter.placeRoundEnded()

    // 못 한 키 2개 몫이 빠진다.
    #expect((meter.completed, meter.total) == (350, 350))
  }

  @Test("알리지 않고 끝난 회차는 hold 를 놓기 전이면 예약을 두고, 놓은 뒤면 예약을 뺀다")
  func keepsPlaceReserveUntilIndexingEnded() {
    var meter = ContinuedIndexingMeter(reservesPlaceRound: true)
    meter.receive(Self.text(done: 0, pending: 2))
    #expect(meter.total == 400 + 10500)

    meter.placeRoundStarted()
    meter.placeRoundEnded()
    #expect(meter.total == 400 + 10500)
    meter.receive(Self.text(done: 2, pending: 0))
    meter.indexingEnded()
    // 회차 2 가 아직 올 수 있다.
    #expect((meter.completed, meter.total) == (400, 400 + 10500))
    meter.placeRoundStarted()
    meter.placeRoundEnded()

    #expect((meter.completed, meter.total) == (400, 400))
  }

  @Test("회차가 돌 수 없으면 장소 몫을 미리 넣지 않는다")
  func noPlaceReserveWithoutRound() {
    var meter = ContinuedIndexingMeter(reservesPlaceRound: false)

    meter.receive(Self.text(done: 0, pending: 2))

    #expect((meter.completed, meter.total) == (0, 400))
  }

  @Test("새 사진·건너뜀·재시작·hold 놓음·회차 차례 동안 완료는 줄지 않고 전체는 완료 이상, 1 이상이다")
  func totalStaysAboveCompleted() {
    var meter = ContinuedIndexingMeter(reservesPlaceRound: true)
    let steps: [(inout ContinuedIndexingMeter) -> Void] = [
      { $0.receive(IndexingProgress(totalCount: 10, indexedCount: 2, skippedCount: 0)) },
      { $0.receive(IndexingProgress(totalCount: 10, indexedCount: 4, skippedCount: 1)) },
      { $0.receive(IndexingProgress(totalCount: 13, indexedCount: 4, skippedCount: 1)) },
      { $0.runRestarted() },
      { $0.receive(IndexingProgress(totalCount: 13, indexedCount: 4, skippedCount: 0)) },
      { $0.receive(IndexingProgress(totalCount: 13, indexedCount: 13, skippedCount: 0, pendingTextCount: 3)) },
      { $0.receive(IndexingProgress(
        totalCount: 13,
        indexedCount: 13,
        skippedCount: 0,
        pendingTextCount: 1,
        recognizedTextCount: 1,
        skippedTextCount: 1
      )) },
      { $0.indexingEnded() },
      { $0.placeRoundStarted() },
      { $0.placeProgress(TripPlacePrefetchProgress(doneCount: 0, totalCount: 2)) },
      { $0.placeProgress(TripPlacePrefetchProgress(doneCount: 1, totalCount: 2)) },
      { $0.placeRoundEnded() },
    ]
    var previous: Int64 = 0

    for step in steps {
      step(&meter)
      #expect(meter.completed >= previous)
      #expect(meter.total >= meter.completed)
      #expect(meter.total >= 1)
      previous = meter.completed
    }
  }

  @Test("hold 를 놓으면 남은 분류·대기 몫이 빠져 전체가 줄고, 그 뒤 분류 진행률은 버린다")
  func indexingEndedDropsRemaining() {
    var meter = ContinuedIndexingMeter()
    meter.receive(IndexingProgress(totalCount: 10, indexedCount: 0, skippedCount: 0))
    meter.receive(IndexingProgress(totalCount: 10, indexedCount: 5, skippedCount: 0, pendingTextCount: 2))
    // 비율 = (2 + 20) ÷ (5 + 100). 남은 5장 × 16 + 5 × 비율 × 200(≈ 209.5 → 210) + 대기 2 × 200.
    #expect((meter.completed, meter.total) == (80, 770))

    meter.indexingEnded()
    #expect((meter.completed, meter.total) == (80, 80))
    meter.receive(IndexingProgress(totalCount: 20, indexedCount: 5, skippedCount: 0))

    #expect((meter.completed, meter.total) == (80, 80))
  }

  @Test("2단계의 장마다 값 다음 같은 처리 수의 배치 값은 완료를 바꾸지 않는다")
  func batchValueAfterPerImageValue() {
    var meter = ContinuedIndexingMeter()
    meter.receive(Self.text(done: 0, pending: 3))
    meter.receive(Self.text(done: 1, pending: 2))
    let afterPerImage = (meter.completed, meter.total)

    meter.receive(Self.text(done: 1, pending: 2))

    #expect(afterPerImage == (200, 600))
    #expect((meter.completed, meter.total) == afterPerImage)
  }

  @Test("큰 보관함에서도 넘치지 않는다")
  func largeLibrary() {
    var meter = ContinuedIndexingMeter(reservesPlaceRound: true)

    meter.receive(IndexingProgress(totalCount: 200_000, indexedCount: 0, skippedCount: 0))
    #expect(meter.total == 200_000 * 56 + 10500)
    meter.receive(IndexingProgress(totalCount: 200_000, indexedCount: 100_000, skippedCount: 0, pendingTextCount: 5000))

    #expect(meter.completed == 1_600_000)
    #expect(meter.total > meter.completed)
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
