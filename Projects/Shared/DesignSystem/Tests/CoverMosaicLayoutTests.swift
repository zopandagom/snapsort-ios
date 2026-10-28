import CoreGraphics
import DesignSystem
import Testing

struct CoverMosaicLayoutTests {
  @Test("1~4장 배치는 단위 칸을 겹치지 않고 채운다", arguments: 1 ... 4)
  func layoutFillsUnitSquareWithoutOverlap(count: Int) {
    let frames = CoverMosaic.layout(count: count)
    #expect(frames.count == count)
    let area = frames.reduce(0) { $0 + $1.width * $1.height }
    #expect(abs(area - 1) < 0.0001)
    for frame in frames {
      #expect(frame.minX >= -0.0001 && frame.minY >= -0.0001)
      #expect(frame.maxX <= 1.0001 && frame.maxY <= 1.0001)
    }
    for (index, frame) in frames.enumerated() {
      for other in frames[(index + 1)...] {
        let overlap = frame.intersection(other)
        #expect(overlap.isNull || overlap.width * overlap.height < 0.0001, "\(frame) 와 \(other) 가 겹친다")
      }
    }
  }

  @Test("0장은 한 칸, 5장 이상은 4칸이다")
  func layoutClampsCount() {
    #expect(CoverMosaic.layout(count: 0) == [CGRect(x: 0, y: 0, width: 1, height: 1)])
    #expect(CoverMosaic.layout(count: -1).count == 1)
    #expect(CoverMosaic.layout(count: 5) == CoverMosaic.layout(count: 4))
    #expect(CoverMosaic.layout(count: 12).count == 4)
  }

  @Test("3장 배치는 첫 칸이 왼쪽 2/3 다")
  func threeTileLayoutLeadsWithLargeTile() throws {
    let first = try #require(CoverMosaic.layout(count: 3).first)
    #expect(first.minX == 0 && first.minY == 0)
    #expect(abs(first.width - 2.0 / 3) < 0.0001)
    #expect(first.height == 1)
  }
}
