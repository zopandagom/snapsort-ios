import Core
import Foundation
import Testing

struct SimilarPhotoGroupingTests {
  private static func ids(_ groups: [SimilarPhotoGroup]) -> [[ImageAsset.ID]] {
    groups.map { $0.photos.map(\.id) }
  }

  @Test("이웃 간격이 정확히 60초면 잇고 60초를 넘으면 끊는다")
  func gapBoundary() {
    let linked = SimilarPhotoGrouping.groups([
      similarPhoto("a", seconds: 0),
      similarPhoto("b", seconds: 60),
    ])
    let cut = SimilarPhotoGrouping.groups([
      similarPhoto("a", seconds: 0),
      similarPhoto("b", seconds: 60.001),
    ])

    #expect(Self.ids(linked) == [["a", "b"]])
    #expect(cut.isEmpty)
  }

  @Test("이웃 거리가 기준 바로 안이면 잇고 바로 밖이면 끊는다")
  func linkDistanceBoundary() {
    let linked = SimilarPhotoGrouping.groups([
      similarPhoto("a", seconds: 0, x: 0),
      similarPhoto("b", seconds: 1, x: 0.34),
    ])
    let cut = SimilarPhotoGrouping.groups([
      similarPhoto("a", seconds: 0, x: 0),
      similarPhoto("b", seconds: 1, x: 0.36),
    ])

    #expect(Self.ids(linked) == [["a", "b"]])
    #expect(cut.isEmpty)
  }

  @Test("첫 장과 거리가 정확히 0.5 면 잇고 넘으면 끊는다. 이웃 거리는 기준 안이다")
  func spreadBoundary() {
    let linked = SimilarPhotoGrouping.groups([
      similarPhoto("a", seconds: 0, x: 0),
      similarPhoto("b", seconds: 1, x: 0.25),
      similarPhoto("c", seconds: 2, x: 0.5),
    ])
    let cut = SimilarPhotoGrouping.groups([
      similarPhoto("a", seconds: 0, x: 0),
      similarPhoto("b", seconds: 1, x: 0.25),
      similarPhoto("c", seconds: 2, x: 0.5),
      similarPhoto("d", seconds: 3, x: 0.75),
    ])

    #expect(Self.ids(linked) == [["a", "b", "c"]])
    // d 는 c 와 0.25 지만 a 와 0.75 라 끊기고, 홀로 남아 버려진다.
    #expect(Self.ids(cut) == [["a", "b", "c"]])
  }

  @Test("끊긴 뒤에는 이전 묶음과 다시 비교하지 않는다")
  func doesNotRejoinPreviousGroup() {
    let groups = SimilarPhotoGrouping.groups([
      similarPhoto("a", seconds: 0, x: 0),
      similarPhoto("b", seconds: 1, x: 0),
      similarPhoto("far", seconds: 2, x: 2),
      similarPhoto("c", seconds: 3, x: 0),
      similarPhoto("d", seconds: 4, x: 0),
    ])

    // c 는 a·b 와 같은 벡터지만 바로 앞 장(far)과 멀어 새 묶음이 된다.
    #expect(Self.ids(groups).sorted { $0[0] < $1[0] } == [["a", "b"], ["c", "d"]])
  }

  @Test("한 장뿐인 묶음은 버린다")
  func dropsSingletons() {
    let groups = SimilarPhotoGrouping.groups([
      similarPhoto("alone", seconds: 0),
      similarPhoto("later", seconds: 1000),
    ])

    #expect(groups.isEmpty)
  }

  @Test("남길 장은 픽셀 수가 가장 큰 장이고, 같으면 최신, 같은 시각이면 식별자가 작은 쪽이다")
  func keptPhoto() throws {
    let bySize = try #require(SimilarPhotoGrouping.groups([
      similarPhoto("small", seconds: 0, width: 100, height: 100),
      similarPhoto("large", seconds: 1, width: 4000, height: 3000),
      similarPhoto("medium", seconds: 2, width: 2000, height: 1500),
    ]).first)
    let byDate = try #require(SimilarPhotoGrouping.groups([
      similarPhoto("older", seconds: 0),
      similarPhoto("newer", seconds: 1),
    ]).first)
    let byID = try #require(SimilarPhotoGrouping.groups([
      similarPhoto("b", seconds: 0),
      similarPhoto("a", seconds: 0),
    ]).first)
    let negative = try #require(SimilarPhotoGrouping.groups([
      similarPhoto("broken", seconds: 0, width: -5000, height: -5000),
      similarPhoto("normal", seconds: 1, width: 10, height: 10),
    ]).first)

    #expect(bySize.keptID == "large")
    #expect(byDate.keptID == "newer")
    #expect(byID.keptID == "a")
    // 음수 크기는 0 으로 본다(곱하면 양수가 되지 않게).
    #expect(negative.keptID == "normal")
  }

  @Test("남길 수 없는 장은 남길 장으로 고르지 않고, 묶음이 모두 그렇다면 전체에서 고른다")
  func unkeepablePhoto() throws {
    let photos = [
      similarPhoto("small", seconds: 0, width: 100, height: 100),
      similarPhoto("large", seconds: 1, width: 4000, height: 3000),
      similarPhoto("medium", seconds: 2, width: 2000, height: 1500),
    ]
    let skipped = try #require(SimilarPhotoGrouping.groups(photos, unkeepable: ["large"]).first)
    let allUnkeepable = try #require(
      SimilarPhotoGrouping.groups(photos, unkeepable: ["small", "large", "medium"]).first
    )

    #expect(skipped.keptID == "medium")
    #expect(skipped.photos.map(\.id) == ["small", "large", "medium"])
    #expect(allUnkeepable.keptID == "large")
  }

  @Test("최근 묶음이 먼저이고 묶음 안은 촬영 순서이며 식별자는 첫 장이다")
  func ordering() {
    let groups = SimilarPhotoGrouping.groups([
      similarPhoto("old1", seconds: 0),
      similarPhoto("old2", seconds: 1),
      similarPhoto("new1", seconds: 1000),
      similarPhoto("new2", seconds: 1001),
      similarPhoto("new3", seconds: 1002),
    ])

    #expect(Self.ids(groups) == [["new1", "new2", "new3"], ["old1", "old2"]])
    #expect(groups.map(\.id) == ["new1", "old1"])
  }

  @Test("빼는 사진은 묶기 전에 빠져 가운데 장을 빼면 간격이 넓어져 끊긴다")
  func excludingBeforeGrouping() {
    let photos = [
      similarPhoto("a", seconds: 0),
      similarPhoto("b", seconds: 50),
      similarPhoto("c", seconds: 100),
    ]

    #expect(Self.ids(SimilarPhotoGrouping.groups(photos)) == [["a", "b", "c"]])
    #expect(SimilarPhotoGrouping.groups(photos, excluding: ["b"]).isEmpty)
    #expect(Self.ids(SimilarPhotoGrouping.groups(photos, excluding: ["c"])) == [["a", "b"]])
  }

  @Test("생성일 없는 사진과 스크린샷은 묶지 않는다")
  func ignoresUndatedAndScreenshots() {
    let groups = SimilarPhotoGrouping.groups([
      similarPhoto("a", seconds: 0),
      similarPhoto("undated", seconds: nil),
      similarPhoto("shot", seconds: 1, isScreenshot: true),
      similarPhoto("b", seconds: 2),
    ])

    #expect(Self.ids(groups) == [["a", "b"]])
  }

  @Test("정렬되지 않은 입력도 생성일 순으로 묶고, 같은 식별자는 처음 것만 쓴다")
  func unsortedAndDuplicates() {
    let groups = SimilarPhotoGrouping.groups([
      similarPhoto("c", seconds: 2),
      similarPhoto("a", seconds: 0),
      similarPhoto("b", seconds: 1),
      similarPhoto("a", seconds: 500),
    ])

    #expect(Self.ids(groups) == [["a", "b", "c"]])
  }

  @Test("시간 이웃이 없는 사진은 빠지고 간격 60초는 이웃이다")
  func linkableIDs() {
    let ids = SimilarPhotoGrouping.linkableIDs(in: [
      similarAsset("alone", seconds: 0),
      similarAsset("a", seconds: 1000),
      similarAsset("b", seconds: 1060),
      similarAsset("c", seconds: 1120.5),
      similarAsset("undated", seconds: nil),
    ])

    #expect(ids == ["a", "b"])
  }

  @Test("시간 이웃으로 미리 거른 입력의 묶음은 거르지 않은 입력과 같다")
  func linkablePrefilterKeepsGroups() {
    var generator = SplitMix64(seed: 20_261_026)
    for _ in 0 ..< 20 {
      var seconds: TimeInterval = 0
      var photos: [FeaturePrintedPhoto] = []
      for index in 0 ..< 200 {
        seconds += TimeInterval(generator.next() % 120)
        let x = Float(generator.next() % 100) / 100
        photos.append(similarPhoto("p\(index)", seconds: seconds, x: x))
      }
      let excluding = Set(photos.map(\.id).filter { _ in generator.next() % 10 == 0 })
      let linkable = SimilarPhotoGrouping.linkableIDs(in: photos.map(\.asset))
      let filtered = photos.filter { linkable.contains($0.id) }

      #expect(
        SimilarPhotoGrouping.groups(filtered, excluding: excluding)
          == SimilarPhotoGrouping.groups(photos, excluding: excluding)
      )
    }
  }
}

/// 고정 시드 난수. 테스트가 늘 같은 입력을 만든다.
private struct SplitMix64 {
  private var state: UInt64

  init(seed: UInt64) {
    self.state = seed
  }

  mutating func next() -> UInt64 {
    self.state &+= 0x9E37_79B9_7F4A_7C15
    var value = self.state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}
