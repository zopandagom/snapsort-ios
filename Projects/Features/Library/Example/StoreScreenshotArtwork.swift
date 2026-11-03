import CoreGraphics
import CoreText
import Foundation

/// 스토어 스크린샷 시나리오(`ExampleScenario.storeScreenshots`)의 사진 자리 그림. 레포에 이미지 파일을 두지 않으려고 코드로 그린다.
/// 사람 얼굴·실제 장소 사진·실제 앱·서비스 화면·실제 브랜드 로고를 흉내 내지 않는다. 글자는 모두 지어낸 값이다
/// (docs/CONVENTIONS.md §4 스토어 스크린샷 데이터).
/// 같은 입력이면 같은 그림이다(난수 없음). 좌표는 왼쪽 위 원점으로 뒤집어 그린다.
enum StoreScreenshotArtwork {
  /// 사진형(카메라 사진) 그림 크기.
  static let photoSize = CGSize(width: 640, height: 480)
  /// 캡처형(세로 스크린샷) 그림 크기.
  static let captureSize = CGSize(width: 540, height: 1170)
  /// 기프티콘 그림 높이. 너비는 `StoreScreenshotData.gifticonBaseWidth + 번호` 로 장을 가른다.
  static let gifticonHeight = 1950
  /// 기프티콘 그림의 바코드 자리(바르게 돌린 기준 정규화, 원점 왼쪽 위). 바코드 대역 결과의 박스와 같다.
  static let barcodeBox = CGRect(x: 0.12, y: 0.66, width: 0.76, height: 0.1)

  enum Scene: Hashable {
    case landscape(Int)
    case food(Int)
    case people(Int)
    case pet(Int)
    case other(Int)
    /// 여행 사진: 여행 0 바다·분화구 언덕, 1 단풍 언덕, 2 해변. 둘째 값은 변형.
    case trip(Int, Int)
  }

  struct RGB: Hashable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) {
      self.red = red
      self.green = green
      self.blue = blue
    }

    static let white = RGB(1, 1, 1)
    static let black = RGB(0, 0, 0)
    static let ink = RGB(0.16, 0.13, 0.15)
    static let gray = RGB(0.45, 0.42, 0.44)

    /// 흰색 쪽으로 `amount` 만큼 밝힌 색.
    func lightened(_ amount: CGFloat) -> RGB {
      RGB(min(self.red + amount, 1), min(self.green + amount, 1), min(self.blue + amount, 1))
    }
  }

  struct Palette {
    let top: RGB
    let bottom: RGB
    let accent: RGB
  }

  static let palettes: [Palette] = [
    Palette(top: RGB(0.62, 0.80, 0.95), bottom: RGB(0.95, 0.88, 0.80), accent: RGB(0.98, 0.84, 0.45)),
    Palette(top: RGB(0.98, 0.72, 0.62), bottom: RGB(0.99, 0.90, 0.78), accent: RGB(1.0, 0.95, 0.70)),
    Palette(top: RGB(0.45, 0.62, 0.86), bottom: RGB(0.80, 0.88, 0.96), accent: RGB(1.0, 1.0, 0.95)),
    Palette(top: RGB(0.78, 0.70, 0.92), bottom: RGB(0.98, 0.84, 0.86), accent: RGB(1.0, 0.92, 0.80)),
    Palette(top: RGB(0.55, 0.82, 0.80), bottom: RGB(0.92, 0.96, 0.90), accent: RGB(0.99, 0.90, 0.55)),
    Palette(top: RGB(0.96, 0.62, 0.55), bottom: RGB(0.60, 0.45, 0.62), accent: RGB(1.0, 0.80, 0.55)),
  ]

  static func palette(_ variant: Int) -> Palette {
    self.palettes[variant % self.palettes.count]
  }

  static func photo(_ scene: Scene) -> CGImage {
    self.render(self.photoSize) { context, size in
      switch scene {
      case let .landscape(variant):
        self.drawLandscape(context, size: size, palette: self.palette(variant), phase: variant % 3)
      case let .trip(trip, variant):
        self.drawTrip(context, size: size, trip: trip, variant: variant)
      case let .food(variant):
        self.drawFood(context, size: size, variant: variant)
      case let .people(variant):
        self.drawPeople(context, size: size, variant: variant)
      case let .pet(variant):
        self.drawPet(context, size: size, variant: variant)
      case let .other(variant):
        self.drawPattern(context, size: size, variant: variant)
      }
    }
  }
}

// MARK: - 사진형

extension StoreScreenshotArtwork {
  private static func drawLandscape(_ context: CGContext, size: CGSize, palette: Palette, phase: Int) {
    self.fillGradient(context, size: size, top: palette.top, bottom: palette.bottom)
    self.fill(context, palette.accent)
    context.fillEllipse(in: CGRect(x: size.width * 0.68, y: size.height * 0.14, width: 90, height: 90))
    self.fill(context, .white, alpha: 0.85)
    for (x, y) in [(0.12, 0.18), (0.40, 0.10)] {
      context.fillEllipse(in: CGRect(x: size.width * x, y: size.height * y, width: 120, height: 40))
      context.fillEllipse(in: CGRect(x: size.width * x + 40, y: size.height * y - 18, width: 80, height: 50))
    }
    let layers: [(CGFloat, RGB)] = [
      (0.52, RGB(0.52, 0.66, 0.62)),
      (0.64, RGB(0.36, 0.54, 0.46)),
      (0.78, RGB(0.24, 0.42, 0.36)),
    ]
    for (index, layer) in layers.enumerated() {
      self.fill(context, layer.1)
      self.wave(
        context,
        size: size,
        baseline: size.height * layer.0,
        amplitude: 40 - CGFloat(index * 8),
        phase: CGFloat(phase + index) * 1.3
      )
    }
  }

  private static func drawTrip(_ context: CGContext, size: CGSize, trip: Int, variant: Int) {
    let palette = self.palette(variant + trip * 2)
    self.fillGradient(context, size: size, top: palette.top, bottom: palette.bottom)
    self.fill(context, palette.accent)
    context.fillEllipse(in: CGRect(
      x: size.width * (0.15 + CGFloat(variant % 3) * 0.25),
      y: size.height * 0.12,
      width: 80,
      height: 80
    ))
    switch trip {
    case 0:
      self.drawCraterSea(context, size: size, variant: variant)
    case 1:
      // 단풍 든 둥근 언덕.
      let colors = [RGB(0.90, 0.56, 0.32), RGB(0.80, 0.36, 0.28), RGB(0.62, 0.50, 0.30)]
      for (index, color) in colors.enumerated() {
        self.fill(context, color)
        self.wave(
          context,
          size: size,
          baseline: size.height * (0.5 + CGFloat(index) * 0.13),
          amplitude: 46,
          phase: CGFloat(variant + index)
        )
      }
    default:
      // 모래사장과 파도.
      self.fill(context, RGB(0.30, 0.62, 0.80))
      context.fill(CGRect(x: 0, y: size.height * 0.5, width: size.width, height: size.height * 0.3))
      self.fill(context, .white, alpha: 0.8)
      self.wave(context, size: size, baseline: size.height * 0.74, amplitude: 10, phase: CGFloat(variant))
      self.fill(context, RGB(0.96, 0.88, 0.70))
      self.wave(context, size: size, baseline: size.height * 0.78, amplitude: 12, phase: CGFloat(variant))
    }
  }

  /// 바다 위 평평한 분화구 언덕.
  private static func drawCraterSea(_ context: CGContext, size: CGSize, variant: Int) {
    let width = size.width
    let height = size.height
    self.fill(context, RGB(0.36, 0.52, 0.40))
    let path = CGMutablePath()
    path.move(to: CGPoint(x: width * 0.2, y: height * 0.62))
    path.addCurve(
      to: CGPoint(x: width * 0.42, y: height * 0.36),
      control1: CGPoint(x: width * 0.3, y: height * 0.6),
      control2: CGPoint(x: width * 0.34, y: height * 0.38)
    )
    path.addLine(to: CGPoint(x: width * 0.66, y: height * 0.36))
    path.addCurve(
      to: CGPoint(x: width * 0.9, y: height * 0.62),
      control1: CGPoint(x: width * 0.74, y: height * 0.38),
      control2: CGPoint(x: width * 0.8, y: height * 0.6)
    )
    path.closeSubpath()
    context.addPath(path)
    context.fillPath()
    self.fill(context, RGB(0.22, 0.48, 0.70))
    context.fill(CGRect(x: 0, y: height * 0.6, width: width, height: height * 0.4))
    self.fill(context, .white, alpha: 0.5)
    for row in 0 ..< 4 {
      let x = CGFloat(row * 90 + variant * 30).truncatingRemainder(dividingBy: width)
      context.fill(CGRect(x: x, y: height * (0.68 + CGFloat(row) * 0.07), width: 120, height: 4))
    }
  }

  private static func drawFood(_ context: CGContext, size: CGSize, variant: Int) {
    let tables = [RGB(0.86, 0.74, 0.60), RGB(0.94, 0.92, 0.88), RGB(0.48, 0.36, 0.30), RGB(0.80, 0.86, 0.82)]
    self.fill(context, tables[variant % tables.count])
    context.fill(CGRect(origin: .zero, size: size))
    // 접시 가운데(비율)와 지름.
    let plates = [
      CGRect(x: 0.5, y: 0.5, width: 300, height: 300),
      CGRect(x: 0.18, y: 0.2, width: 150, height: 150),
      CGRect(x: 0.84, y: 0.78, width: 170, height: 170),
    ]
    let foods = [RGB(0.92, 0.52, 0.30), RGB(0.42, 0.66, 0.36), RGB(0.96, 0.80, 0.40), RGB(0.78, 0.30, 0.34)]
    for (index, plate) in plates.enumerated() {
      let diameter = plate.width
      let rect = CGRect(
        x: size.width * plate.minX - diameter / 2,
        y: size.height * plate.minY - diameter / 2,
        width: diameter,
        height: diameter
      )
      self.fill(context, .black, alpha: 0.08)
      context.fillEllipse(in: rect.offsetBy(dx: 6, dy: 8))
      self.fill(context, .white)
      context.fillEllipse(in: rect)
      self.fill(context, foods[(variant + index) % foods.count])
      context.fillEllipse(in: rect.insetBy(dx: diameter * 0.22, dy: diameter * 0.22))
      self.fill(context, foods[(variant + index + 1) % foods.count])
      context.fillEllipse(in: CGRect(
        x: rect.midX - diameter * 0.12,
        y: rect.midY - diameter * 0.2,
        width: diameter * 0.2,
        height: diameter * 0.2
      ))
    }
  }

  private static func drawPeople(_ context: CGContext, size: CGSize, variant: Int) {
    let palette = self.palette(variant + 3)
    self.fillGradient(context, size: size, top: palette.bottom, bottom: palette.top)
    let count = variant % 3 + 1
    let shirts = [RGB(0.95, 0.60, 0.66), RGB(0.50, 0.62, 0.86), RGB(0.98, 0.82, 0.50)]
    for index in 0 ..< count {
      let centerX = size.width * (CGFloat(index) + 1) / CGFloat(count + 1)
      let headSize: CGFloat = 110
      self.fill(context, shirts[(index + variant) % shirts.count])
      context.addPath(CGPath(
        roundedRect: CGRect(x: centerX - 100, y: size.height * 0.62, width: 200, height: size.height * 0.5),
        cornerWidth: 90,
        cornerHeight: 90,
        transform: nil
      ))
      context.fillPath()
      self.fill(context, RGB(0.93, 0.80, 0.70))
      context.fillEllipse(in: CGRect(
        x: centerX - headSize / 2,
        y: size.height * 0.36,
        width: headSize,
        height: headSize
      ))
      self.fill(context, RGB(0.30, 0.22, 0.20))
      context.fillEllipse(in: CGRect(
        x: centerX - headSize / 2 - 4,
        y: size.height * 0.33,
        width: headSize + 8,
        height: 60
      ))
    }
  }

  private static func drawPet(_ context: CGContext, size: CGSize, variant: Int) {
    let palette = self.palette(variant + 1)
    self.fillGradient(context, size: size, top: palette.bottom, bottom: palette.top)
    let furs = [RGB(0.96, 0.78, 0.52), RGB(0.55, 0.50, 0.48), RGB(0.98, 0.96, 0.92), RGB(0.40, 0.30, 0.24)]
    let center = CGPoint(x: size.width / 2, y: size.height * 0.55)
    self.fill(context, furs[variant % furs.count])
    for side in [-1.0, 1.0] {
      if variant.isMultiple(of: 2) {
        // 고양이: 세모 귀.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center.x + side * 150, y: center.y - 60))
        path.addLine(to: CGPoint(x: center.x + side * 120, y: center.y - 210))
        path.addLine(to: CGPoint(x: center.x + side * 40, y: center.y - 130))
        path.closeSubpath()
        context.addPath(path)
        context.fillPath()
      } else {
        // 강아지: 늘어진 귀.
        context.fillEllipse(in: CGRect(x: center.x + side * 150 - 50, y: center.y - 120, width: 100, height: 200))
      }
    }
    context.fillEllipse(in: CGRect(x: center.x - 160, y: center.y - 150, width: 320, height: 290))
    self.fill(context, RGB(0.15, 0.12, 0.12))
    for side in [-1.0, 1.0] {
      context.fillEllipse(in: CGRect(x: center.x + side * 60 - 14, y: center.y - 40, width: 28, height: 32))
    }
    context.fillEllipse(in: CGRect(x: center.x - 18, y: center.y + 20, width: 36, height: 24))
  }

  private static func drawPattern(_ context: CGContext, size: CGSize, variant: Int) {
    let palette = self.palette(variant + 2)
    self.fill(context, palette.bottom)
    context.fill(CGRect(origin: .zero, size: size))
    self.fill(context, palette.top, alpha: 0.7)
    for row in 0 ..< 6 {
      for column in 0 ..< 8 where (row + column + variant).isMultiple(of: 2) {
        context.fillEllipse(in: CGRect(x: CGFloat(column) * 84 + 10, y: CGFloat(row) * 84 + 10, width: 60, height: 60))
      }
    }
  }
}

// MARK: - 그리기 도구

extension StoreScreenshotArtwork {
  /// 글자 크기·굵기·색.
  struct TextStyle {
    let size: CGFloat
    var bold = false
    var color: RGB = .ink
  }

  enum TextAlignment {
    case leading, center, trailing
  }

  /// 왼쪽 위 원점으로 뒤집은 컨텍스트에 그린다. 글자는 `drawText` 가 다시 바로 세운다.
  static func render(_ size: CGSize, draw: (CGContext, CGSize) -> Void) -> CGImage {
    let width = Int(size.width)
    let height = Int(size.height)
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return .colored(index: width) }
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    draw(context, size)
    return context.makeImage() ?? .colored(index: width)
  }

  static func fill(_ context: CGContext, _ color: RGB, alpha: CGFloat = 1) {
    context.setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: alpha)
  }

  static func fillGradient(_ context: CGContext, size: CGSize, top: RGB, bottom: RGB) {
    let components: [CGFloat] = [top.red, top.green, top.blue, 1, bottom.red, bottom.green, bottom.blue, 1]
    guard let gradient = CGGradient(
      colorSpace: CGColorSpaceCreateDeviceRGB(),
      colorComponents: components,
      locations: [0, 1],
      count: 2
    ) else { return }
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
  }

  /// `baseline` 위로 물결치는 면을 아래 끝까지 채운다.
  static func wave(_ context: CGContext, size: CGSize, baseline: CGFloat, amplitude: CGFloat, phase: CGFloat) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: size.height))
    var x: CGFloat = 0
    while x <= size.width {
      path.addLine(to: CGPoint(x: x, y: baseline - amplitude * sin(x / size.width * .pi * 2 + phase)))
      x += 8
    }
    path.addLine(to: CGPoint(x: size.width, y: size.height))
    path.closeSubpath()
    context.addPath(path)
    context.fillPath()
  }

  /// `point` 의 가로(정렬 기준)·세로(글자 윗선)에 한 줄을 그린다. 뒤집은 컨텍스트에서 바로 서게 글자 행렬을 뒤집는다.
  static func drawText(
    _ context: CGContext,
    _ text: String,
    _ style: TextStyle,
    at point: CGPoint,
    alignment: TextAlignment = .leading
  ) {
    let font = CTFontCreateUIFontForLanguage(style.bold ? .emphasizedSystem : .system, style.size, "ko" as CFString)
      ?? CTFontCreateWithName("Helvetica" as CFString, style.size, nil)
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
        red: style.color.red,
        green: style.color.green,
        blue: style.color.blue,
        alpha: 1
      ),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
    let originX = switch alignment {
    case .leading: point.x
    case .center: point.x - lineWidth / 2
    case .trailing: point.x - lineWidth
    }
    context.saveGState()
    context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    context.textPosition = CGPoint(x: originX, y: point.y + CTFontGetAscent(font))
    CTLineDraw(line, context)
    context.restoreGState()
  }
}
