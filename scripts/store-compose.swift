// 스토어 스크린샷 합성: 시뮬레이터 캡처(1320×2868) 위에 캡션을 얹은 1320×2868 알파 없는 PNG 를 만든다.
// scripts/store-screenshots.sh 가 부른다 (docs/CONVENTIONS.md §5). 외부 의존 없음(Foundation·CoreGraphics·CoreText·ImageIO).
// 사용: swift scripts/store-compose.swift <캡션.tsv> <입력 폴더> <출력 폴더> <캡션 글꼴 파일>
//   캡션 줄 `<줄기>\t<첫 줄>\t<둘째 줄(선택)>` 마다 <입력 폴더>/<줄기>.png 를 읽어 <출력 폴더>/<줄기>.png 를 쓴다.
// 배치: 위 캡션 영역(첫 줄 잉크색, 둘째 줄 강조색) + 소프트 로즈 그라데이션 위에 줄인 화면 전체(모서리 둥글게).
// 캡션 글꼴은 인자로 받은 글꼴 파일(앱과 같은 나눔스퀘어라운드 EB, DesignSystem Resources/Fonts)로만 그린다. 시스템에 설치하지 않고,
// 파일이 없거나 읽지 못하면 시스템 글꼴로 떨어지지 않고 실패한다. 같은 파일·같은 입력이면 결과 바이트가 같다
// (글자 래스터화는 macOS CoreText 라 macOS 버전이 바뀌면 달라질 수 있다).
import CoreGraphics
import CoreText
import Foundation
import ImageIO

let canvasWidth = 1320
let canvasHeight = 2868

/// 배치 상수(픽셀, 위에서 잰 값). 화면 전체(아래 검색 필드·정리 삭제 단추 포함)가 캔버스 안에 들어가게 잡았다(아래 여백 약 88).
enum Layout {
  static let captionTop: CGFloat = 130
  static let captionBottom: CGFloat = 560
  static let captionMaxWidth: CGFloat = 1160
  static let lineGap: CGFloat = 0.22 // 글자 크기 대비 줄 사이
  static let fontSize: CGFloat = 104
  static let minFontSize: CGFloat = 72
  static let fontStep: CGFloat = 6
  static let screenScale: CGFloat = 0.76
  static let screenTop: CGFloat = 600
  static let screenCornerRadius: CGFloat = 110
  static let shadowBlur: CGFloat = 60
  static let shadowOffsetY: CGFloat = 16
}

/// DesignSystem `SnapColor` 라이트 값과 같은 색.
enum Palette {
  static let blush = rgb(0xFFE1EA)
  static let background = rgb(0xFFF8F5)
  static let ink = rgb(0x2A2226)
  static let accent = rgb(0xC42854)
  static let shadow = CGColor(srgbRed: 0x2A / 255, green: 0x22 / 255, blue: 0x26 / 255, alpha: 0.18)

  static func rgb(_ hex: Int) -> CGColor {
    CGColor(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1
    )
  }
}

struct Caption {
  let stem: String
  let lines: [String]
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("FAIL 합성: \(message)\n".utf8))
  exit(1)
}

func readCaptions(_ path: String) -> [Caption] {
  guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { fail("캡션 파일을 읽지 못했습니다: \(path)") }
  var captions: [Caption] = []
  for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
    let line = String(raw)
    if line.trimmingCharacters(in: .whitespaces).isEmpty || line.hasPrefix("#") {
      continue
    }
    let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard (2 ... 3).contains(columns.count), !columns[0].isEmpty, !columns[1].isEmpty else {
      fail("캡션 줄 형식이 틀립니다(줄기\\t첫 줄\\t둘째 줄): \(line)")
    }
    let lines = columns.dropFirst().filter { !$0.isEmpty }
    captions.append(Caption(stem: columns[0], lines: Array(lines)))
  }
  guard !captions.isEmpty else { fail("캡션이 없습니다: \(path)") }
  return captions
}

func loadImage(_ path: String, stem: String) -> CGImage {
  guard
    let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else { fail("\(stem) 입력이 없거나 읽지 못했습니다: \(path)") }
  guard image.width == canvasWidth, image.height == canvasHeight else {
    fail("\(stem) 입력이 \(canvasWidth)x\(canvasHeight) 가 아닙니다 (\(image.width)x\(image.height))")
  }
  return image
}

/// 글꼴 파일에서 글꼴 서술자를 읽는다. 없거나 글꼴이 아니면 실패.
func loadFontDescriptor(_ path: String) -> CTFontDescriptor {
  let url = URL(fileURLWithPath: path)
  guard FileManager.default.isReadableFile(atPath: path) else { fail("캡션 글꼴 파일이 없거나 읽지 못했습니다: \(path)") }
  guard
    let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
    let descriptor = descriptors.first
  else { fail("캡션 글꼴 파일을 글꼴로 읽지 못했습니다: \(path)") }
  return descriptor
}

func captionFont(_ descriptor: CTFontDescriptor, size: CGFloat) -> CTFont {
  CTFontCreateWithFontDescriptor(descriptor, size, nil)
}

func makeLine(_ text: String, font: CTFont, color: CGColor) -> CTLine {
  let attributes: [NSAttributedString.Key: Any] = [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
  ]
  return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
}

struct TypesetCaption {
  let lines: [CTLine]
  let ascent: CGFloat
  let descent: CGFloat
  let gap: CGFloat

  var lineHeight: CGFloat { self.ascent + self.descent }
  var totalHeight: CGFloat {
    CGFloat(self.lines.count) * self.lineHeight + CGFloat(max(self.lines.count - 1, 0)) * self.gap
  }
}

/// 캡션 영역에 들어갈 때까지 글자 크기를 줄인다. 최소 크기에서도 넘치면 실패.
func typeset(_ caption: Caption, font descriptor: CTFontDescriptor) -> TypesetCaption {
  var size = Layout.fontSize
  while size >= Layout.minFontSize {
    let font = captionFont(descriptor, size: size)
    let lines = caption.lines.enumerated().map { index, text in
      makeLine(text, font: font, color: index == 0 ? Palette.ink : Palette.accent)
    }
    let result = TypesetCaption(
      lines: lines,
      ascent: CTFontGetAscent(font),
      descent: CTFontGetDescent(font),
      gap: size * Layout.lineGap
    )
    let widest = lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }.max() ?? 0
    if widest <= Layout.captionMaxWidth, result.totalHeight <= Layout.captionBottom - Layout.captionTop {
      return result
    }
    size -= Layout.fontStep
  }
  fail("\(caption.stem) 캡션이 너무 깁니다")
}

func drawCaption(
  _ text: TypesetCaption, in context: CGContext, width: CGFloat, flipped: (CGFloat, CGFloat) -> CGFloat
) {
  // 캡션: 영역 안 세로 가운데, 줄마다 가로 가운데.
  var top = Layout.captionTop + (Layout.captionBottom - Layout.captionTop - text.totalHeight) / 2
  for line in text.lines {
    let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    let baseline = flipped(top + text.ascent, 0)
    context.textPosition = CGPoint(x: ((width - lineWidth) / 2).rounded(), y: baseline.rounded())
    CTLineDraw(line, context)
    top += text.lineHeight + text.gap
  }
}

func compose(_ caption: Caption, text: TypesetCaption, screen: CGImage) -> CGImage {
  guard
    let space = CGColorSpace(name: CGColorSpace.sRGB),
    let context = CGContext(
      data: nil, width: canvasWidth, height: canvasHeight, bitsPerComponent: 8, bytesPerRow: 0,
      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )
  else { fail("\(caption.stem) 캔버스를 만들지 못했습니다") }
  let height = CGFloat(canvasHeight)
  let width = CGFloat(canvasWidth)
  // 위에서 잰 y 를 CoreGraphics 좌표(아래가 0)로 바꾼다.
  func flipped(_ top: CGFloat, _ rectHeight: CGFloat) -> CGFloat {
    height - top - rectHeight
  }

  // 배경: 위 blush → 아래 background.
  guard let gradient = CGGradient(
    colorsSpace: space, colors: [Palette.blush, Palette.background] as CFArray, locations: [0, 1]
  ) else { fail("\(caption.stem) 배경을 만들지 못했습니다") }
  context.drawLinearGradient(
    gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: []
  )

  drawCaption(text, in: context, width: width, flipped: flipped)

  // 화면: 줄여서 가로 가운데, 모서리 둥글게, 옅은 그림자.
  let screenWidth = (width * Layout.screenScale).rounded()
  let screenHeight = (height * Layout.screenScale).rounded()
  let frame = CGRect(
    x: ((width - screenWidth) / 2).rounded(),
    y: flipped(Layout.screenTop, screenHeight),
    width: screenWidth,
    height: screenHeight
  )
  let rounded = CGPath(
    roundedRect: frame, cornerWidth: Layout.screenCornerRadius, cornerHeight: Layout.screenCornerRadius,
    transform: nil
  )
  context.saveGState()
  context.setShadow(
    offset: CGSize(width: 0, height: -Layout.shadowOffsetY), blur: Layout.shadowBlur, color: Palette.shadow
  )
  context.addPath(rounded)
  context.setFillColor(Palette.background)
  context.fillPath()
  context.restoreGState()

  context.saveGState()
  context.addPath(rounded)
  context.clip()
  context.interpolationQuality = .high
  context.draw(screen, in: frame)
  context.restoreGState()

  guard let image = context.makeImage() else { fail("\(caption.stem) 결과 이미지를 만들지 못했습니다") }
  return image
}

func writePNG(_ image: CGImage, to path: String, stem: String) {
  guard let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil
  ) else { fail("\(stem) 출력 파일을 만들지 못했습니다: \(path)") }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { fail("\(stem) PNG 를 쓰지 못했습니다: \(path)") }
}

let arguments = CommandLine.arguments
guard arguments.count == 5 else {
  FileHandle.standardError.write(Data("사용: swift store-compose.swift <캡션.tsv> <입력 폴더> <출력 폴더> <캡션 글꼴 파일>\n".utf8))
  exit(2)
}

let captions = readCaptions(arguments[1])
let inputDirectory = arguments[2]
let outputDirectory = arguments[3]
let fontDescriptor = loadFontDescriptor(arguments[4])
do {
  try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
} catch {
  fail("출력 폴더를 만들지 못했습니다: \(outputDirectory)")
}

// 모든 입력·캡션을 먼저 검사해, 한 장이라도 틀리면 아무것도 쓰지 않는다.
let screens = captions.map { loadImage("\(inputDirectory)/\($0.stem).png", stem: $0.stem) }
let texts = captions.map { typeset($0, font: fontDescriptor) }
for index in captions.indices {
  let caption = captions[index]
  let image = compose(caption, text: texts[index], screen: screens[index])
  writePNG(image, to: "\(outputDirectory)/\(caption.stem).png", stem: caption.stem)
}

print("OK 합성 \(captions.count)장 → \(outputDirectory)")
