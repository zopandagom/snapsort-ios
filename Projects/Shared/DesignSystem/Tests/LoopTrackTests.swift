import DesignSystem
import Testing

struct LoopTrackTests {
  @Test("키 시각에서는 키 값이다")
  func valueAtKeys() {
    let track = LoopTrack([0: 0, 0.4: -10, 0.8: 0, 1: 0])
    #expect(track.value(at: 0) == 0)
    #expect(track.value(at: 0.4) == -10)
    #expect(track.value(at: 0.8) == 0)
  }

  @Test("키 사이는 두 키 값 사이이고 가운데에서 반이다")
  func valueBetweenKeys() {
    let track = LoopTrack([0: 0, 0.5: 52, 1: 0])
    #expect(abs(track.value(at: 0.25) - 26) < 0.0001)
    for step in 1 ..< 10 {
      let value = track.value(at: Double(step) / 20)
      #expect(value > 0 && value < 52)
    }
  }

  @Test("주기를 넘는 시각과 음수 시각은 한 주기 안으로 접는다")
  func valueWrapsAroundCycle() {
    let track = SnapProgressArt.cardY
    #expect(abs(track.value(at: 3.3) - track.value(at: 0.3)) < 0.0001)
    #expect(abs(track.value(at: -0.7) - track.value(at: 0.3)) < 0.0001)
  }

  @Test("떨어지는 카드는 칸에 닿기 전에 보이고 다음 주기 시작 전에 사라진다")
  func sortingCardFadesInAndOut() {
    #expect(SnapProgressArt.cardOpacity.value(at: 0) == 0)
    #expect(SnapProgressArt.cardOpacity.value(at: 0.55) == 1)
    #expect(SnapProgressArt.cardOpacity.value(at: 0.7) == 0)
    #expect(SnapProgressArt.cardTravel.value(at: 0.55) == 1)
    #expect(SnapProgressArt.tilePop.value(at: 0.68) > 1)
  }

  @Test("로딩 점은 한 주기 끝에서 제자리로 돌아온다")
  func loadingDotsReturnToBaseline() {
    #expect(SnapLoadingDots.bounce.value(at: 0) == 0)
    #expect(SnapLoadingDots.bounce.value(at: 0.99) == 0)
    #expect(SnapLoadingDots.bounce.value(at: 0.4) == -10)
  }
}
