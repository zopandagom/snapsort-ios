import DesignSystem
import Foundation
import Testing

struct SnapPhotoStackTests {
  @Test("시간이 없으면(동작 줄이기) 멈춘 모양이다")
  func restsWithoutTime() {
    #expect(SnapPhotoStack.pose(at: nil) == .rest)
    #expect(SnapPhotoStack.Pose.rest.cardOffsets.allSatisfy { $0 == 0 })
    #expect(SnapPhotoStack.Pose.rest.sparkles.allSatisfy { $0.scale == 1 && $0.opacity == 1 })
  }

  @Test("장들은 기준 크기에서 위아래 5pt 안에서 서로 엇갈려 뜬다", arguments: stride(from: 0.0, to: 8.0, by: 0.37).map(\.self))
  func floatsWithinDistance(time: Double) {
    let pose = SnapPhotoStack.pose(at: time)
    // 그림 좌표(100)의 거리를 기준 크기(pt)로 옮긴다.
    let halfInPoints = pose.cardOffsets.map { abs($0) * SnapPhotoStack.referenceSize / 100 }
    #expect(pose.cardOffsets.count == 3)
    #expect(halfInPoints.allSatisfy { $0 <= SnapPhotoStack.floatDistance / 2 + 0.0001 })
    #expect(Set(pose.cardOffsets.map { ($0 * 1000).rounded() }).count > 1)
  }

  @Test("반짝이는 0.7~1.15배, 불투명도 0.5~1 사이에서 반 주기씩 엇갈려 깜빡인다", arguments: stride(from: 0.0, to: 4.4, by: 0.13).map(\.self))
  func twinklesWithinRange(time: Double) {
    let sparkles = SnapPhotoStack.pose(at: time).sparkles
    #expect(sparkles.count == 2)
    for sparkle in sparkles {
      #expect(sparkle.scale >= 0.7 - 0.0001 && sparkle.scale <= 1.15 + 0.0001)
      #expect(sparkle.opacity >= 0.5 - 0.0001 && sparkle.opacity <= 1 + 0.0001)
    }
    // 반 주기 엇갈림: 두 반짝이의 세기 합은 늘 같다.
    let levels = sparkles.map { ($0.opacity - 0.5) / 0.5 }
    #expect(abs(levels[0] + levels[1] - 1) < 0.0001)
  }

  @Test("주기는 떠 있기 4초, 깜빡임 2.2초다")
  func periods() {
    #expect(SnapPhotoStack.floatPeriod == 4)
    #expect(SnapPhotoStack.twinklePeriod == 2.2)
    let start = SnapPhotoStack.pose(at: 1)
    let later = SnapPhotoStack.pose(at: 1 + SnapPhotoStack.floatPeriod * 11)
    for (first, second) in zip(start.cardOffsets, later.cardOffsets) {
      #expect(abs(first - second) < 0.0001)
    }
  }
}
