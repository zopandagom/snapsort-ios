// 스토어 스크린샷 촬영의 화면 안정 판정: 연속으로 찍은 두 장을 비교해 "다 그려져 멈춘 화면"인지 답한다.
// scripts/store-screenshots.sh 가 swiftc -O 로 컴파일해 화면마다 반복해서 부른다 (docs/CONVENTIONS.md §5).
// 외부 의존 없음(Foundation·CoreGraphics·ImageIO). 상태를 갖지 않는다(파일 두 개 → 판정 하나). 반복·시한은 스크립트가 맡는다.
// 사용: store-frame <앞 장.png> <뒤 장.png>   → stdout 한 줄 + 종료 코드
// 판정 순서(앞에서 걸리면 거기서 끝):
//   ① 2 `오류: <파일>: <이유>`  인자 개수 틀림·읽을 수 없음·1320×2868 아님·두 장 크기 다름
//   ② 3 `시스템 표시: …`        뒤 장 화면 위 가운데에 다이내믹 아일랜드(실행 직후 1~3초 뜨는 시스템 표시)
//   ③ 4 `빈 화면: 한 색이 …`     뒤 장 가운데 띠가 거의 한 색(흰 실행 화면). 두 장이 같아도 실패한다
//   ④ 1 `다름: 픽셀 N개 (y a~b)`  채널 차가 허용치를 넘는 픽셀이 있음(로딩 표시·지도 타일·전환이 아직 움직임)
//   ⑤ 0 `같음`
// 좌표는 iPhone 17 Pro Max(1320×2868) 전용이다. 스크립트가 기기를 고정하므로, 기기 종류를 바꾸면 아래 상수를 다시 잰다.
import CoreGraphics
import Foundation
import ImageIO

/// 기준값. 근거는 2026-11-03 iPhone 17 Pro Max 시뮬레이터 실측(각 상수 주석).
enum Threshold {
  static let width = 1320
  static let height = 2868
  /// 채널 차가 이 값을 넘으면 다른 픽셀. 한 실행 안 안정 장 차 0, 회차 사이 렌더 잡음 1~2, 지도 타일 차 최대 9 보다 크고
  /// 스피너·아일랜드·홈 표시줄·로딩 차(177~255)보다 작다. 다른 픽셀은 1개도 허용하지 않는다(안정 장은 완전히 같았다).
  static let channelTolerance = 16
  /// 다이내믹 아일랜드 영역(픽셀, 위에서 잰 값)과 "거의 검은" 기준(RGB 모두 이 값 미만).
  static let islandX = 430 ..< 890
  static let islandY = 30 ..< 170
  static let nearBlack = 24
  /// 아일랜드 장은 거의 검은 픽셀 38,576개, 정상 장은 0개 → 약 1/4 을 넘으면 시스템 표시로 본다.
  static let islandPixels = 10000
  /// 가운데 띠의 최빈 색(채널 8단위 양자화) 비율. 흰 실행 화면 1.0, 정상 장 0.32~0.62.
  static let bandY = 200 ..< 2700
  static let blankRatio = 0.95
}

struct Bitmap {
  let width: Int
  let height: Int
  let pixels: [UInt8] // sRGB 8비트 RGBA(알파 앞곱), 위 줄부터

  func offset(_ x: Int, _ y: Int) -> Int {
    (y * self.width + x) * 4
  }
}

enum FrameError: Error {
  case unreadable(String, String)
}

func answer(_ line: String, _ code: Int32) -> Never {
  print(line)
  exit(code)
}

/// PNG 를 같은 sRGB RGBA 비트맵으로 그린다(입력 색공간·알파 형식과 무관하게 같은 기준으로 비교하려고).
func load(_ path: String) throws -> Bitmap {
  guard FileManager.default.fileExists(atPath: path) else { throw FrameError.unreadable(path, "파일이 없습니다") }
  guard
    let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else { throw FrameError.unreadable(path, "PNG 로 읽지 못했습니다") }
  let width = image.width
  let height = image.height
  guard width == Threshold.width, height == Threshold.height else {
    throw FrameError.unreadable(path, "\(Threshold.width)x\(Threshold.height) 가 아닙니다 (\(width)x\(height))")
  }
  var pixels = [UInt8](repeating: 0, count: width * height * 4)
  let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
    guard
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return false }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return true
  }
  guard drawn else { throw FrameError.unreadable(path, "비트맵을 만들지 못했습니다") }
  return Bitmap(width: width, height: height, pixels: pixels)
}

/// ② 아일랜드 영역의 거의 검은 픽셀 수.
func islandPixelCount(_ bitmap: Bitmap) -> Int {
  var count = 0
  let data = bitmap.pixels
  for y in Threshold.islandY {
    for x in Threshold.islandX {
      let index = bitmap.offset(x, y)
      if Int(data[index]) < Threshold.nearBlack, Int(data[index + 1]) < Threshold.nearBlack,
         Int(data[index + 2]) < Threshold.nearBlack
      {
        count += 1
      }
    }
  }
  return count
}

/// ③ 가운데 띠에서 가장 흔한 색(채널 8단위 양자화)의 비율.
func dominantRatio(_ bitmap: Bitmap) -> Double {
  var counts = [Int](repeating: 0, count: 32 * 32 * 32)
  let data = bitmap.pixels
  for y in Threshold.bandY {
    for x in 0 ..< bitmap.width {
      let index = bitmap.offset(x, y)
      counts[(Int(data[index]) >> 3) << 10 | (Int(data[index + 1]) >> 3) << 5 | Int(data[index + 2]) >> 3] += 1
    }
  }
  let total = Threshold.bandY.count * bitmap.width
  return Double(counts.max() ?? 0) / Double(total)
}

struct PixelDiff {
  /// 허용치를 넘는 픽셀 수. `count` 라는 이름이면 SwiftFormat 이 `> 0` 비교를 `isEmpty` 로 바꿔 깨지므로 다른 이름을 쓴다.
  var pixelCount = 0
  var minY = Int.max
  var maxY = -1
}

/// ④ 채널 차가 허용치를 넘는 픽셀 수와 그 y 범위.
func differingPixels(_ lhs: Bitmap, _ rhs: Bitmap) -> PixelDiff {
  var result = PixelDiff()
  lhs.pixels.withUnsafeBufferPointer { left in
    rhs.pixels.withUnsafeBufferPointer { right in
      for y in 0 ..< lhs.height {
        var rowDiffers = false
        for x in 0 ..< lhs.width {
          let index = (y * lhs.width + x) * 4
          if abs(Int(left[index]) - Int(right[index])) > Threshold.channelTolerance
            || abs(Int(left[index + 1]) - Int(right[index + 1])) > Threshold.channelTolerance
            || abs(Int(left[index + 2]) - Int(right[index + 2])) > Threshold.channelTolerance
            || abs(Int(left[index + 3]) - Int(right[index + 3])) > Threshold.channelTolerance
          {
            result.pixelCount += 1
            rowDiffers = true
          }
        }
        if rowDiffers {
          result.minY = min(result.minY, y)
          result.maxY = y
        }
      }
    }
  }
  return result
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else { answer("오류: 인자: 사용법 store-frame <앞 장.png> <뒤 장.png>", 2) }

let before: Bitmap
let after: Bitmap
do {
  before = try load(arguments[1])
  after = try load(arguments[2])
} catch let FrameError.unreadable(path, reason) {
  answer("오류: \(path): \(reason)", 2)
} catch {
  answer("오류: \(error)", 2)
}

let island = islandPixelCount(after)
if island >= Threshold.islandPixels {
  answer("시스템 표시: 화면 위 가운데 검은 픽셀 \(island)개(다이내믹 아일랜드)", 3)
}

let ratio = dominantRatio(after)
if ratio >= Threshold.blankRatio {
  answer("빈 화면: 한 색이 \(String(format: "%.2f", ratio))", 4)
}

let diff = differingPixels(before, after)
if diff.pixelCount > 0 {
  answer("다름: 픽셀 \(diff.pixelCount)개 (y \(diff.minY)~\(diff.maxY))", 1)
}

answer("같음", 0)
