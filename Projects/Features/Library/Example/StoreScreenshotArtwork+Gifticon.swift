import CoreGraphics
import Foundation

/// 기프티콘 그림: 흰 바탕, 위 색 머리띠의 교환처, 가운데 상품 도형·상품명, 바코드 줄무늬와 지어낸 번호, 유효기간 글자.
/// 실제 쿠폰 발급처의 서식·로고를 흉내 내지 않는다.
extension StoreScreenshotArtwork {
  struct Gifticon {
    let place: String
    let product: String
    let shape: ProductShape
    let color: RGB
    let barcodeText: String
    let expiryText: String
  }

  enum ProductShape {
    case cup, cake, bowl, iceCream, card, ticket, book, burger, juice
  }

  static func gifticon(_ gifticon: Gifticon, width: Int) -> CGImage {
    self.render(CGSize(width: width, height: self.gifticonHeight)) { context, size in
      let center = size.width / 2
      self.fill(context, .white)
      context.fill(CGRect(origin: .zero, size: size))
      self.fill(context, gifticon.color)
      context.fill(CGRect(x: 0, y: 0, width: size.width, height: 300))
      self.drawText(
        context,
        gifticon.place,
        TextStyle(size: 64, bold: true, color: .white),
        at: CGPoint(x: center, y: 110),
        alignment: .center
      )
      self.fill(context, gifticon.color, alpha: 0.14)
      context.fillEllipse(in: CGRect(x: center - 250, y: 380, width: 500, height: 500))
      self.drawProduct(context, shape: gifticon.shape, center: CGPoint(x: center, y: 630), color: gifticon.color)
      self.drawText(
        context,
        gifticon.product,
        TextStyle(size: 58, bold: true),
        at: CGPoint(x: center, y: 960),
        alignment: .center
      )
      self.drawText(
        context,
        gifticon.place,
        TextStyle(size: 36, color: .gray),
        at: CGPoint(x: center, y: 1050),
        alignment: .center
      )
      self.drawBarcodeArea(context, size: size, gifticon: gifticon)
    }
  }

  /// 바코드 줄무늬·번호·유효기간.
  private static func drawBarcodeArea(_ context: CGContext, size: CGSize, gifticon: Gifticon) {
    let center = size.width / 2
    let box = self.barcodeBox
    self.drawBars(
      context,
      in: CGRect(
        x: size.width * box.minX,
        y: size.height * box.minY,
        width: size.width * box.width,
        height: size.height * box.height
      ),
      seed: gifticon.barcodeText
    )
    self.drawText(
      context,
      gifticon.barcodeText,
      TextStyle(size: 38),
      at: CGPoint(x: center, y: size.height * box.maxY + 24),
      alignment: .center
    )
    self.drawText(
      context,
      gifticon.expiryText,
      TextStyle(size: 40, bold: true, color: RGB(0.30, 0.28, 0.30)),
      at: CGPoint(x: center, y: size.height * 0.86),
      alignment: .center
    )
  }

  private static func drawProduct(_ context: CGContext, shape: ProductShape, center: CGPoint, color: RGB) {
    switch shape {
    case .cup, .juice:
      self.drawCup(context, center: center, color: color, hasStraw: shape == .juice)
    case .cake:
      self.fill(context, RGB(0.98, 0.94, 0.88))
      context.fill(CGRect(x: center.x - 170, y: center.y - 20, width: 340, height: 170))
      self.fill(context, color.lightened(0.3))
      context.fill(CGRect(x: center.x - 170, y: center.y + 40, width: 340, height: 30))
      self.fill(context, RGB(0.90, 0.24, 0.32))
      context.fillEllipse(in: CGRect(x: center.x - 30, y: center.y - 90, width: 60, height: 60))
    case .bowl:
      self.fill(context, RGB(0.94, 0.40, 0.28))
      context.fillEllipse(in: CGRect(x: center.x - 170, y: center.y - 70, width: 340, height: 120))
      self.fill(context, color)
      self.fillRounded(context, CGRect(x: center.x - 180, y: center.y - 10, width: 360, height: 170), radius: 80)
    case .iceCream:
      let cone = CGMutablePath()
      cone.move(to: CGPoint(x: center.x - 90, y: center.y))
      cone.addLine(to: CGPoint(x: center.x + 90, y: center.y))
      cone.addLine(to: CGPoint(x: center.x, y: center.y + 220))
      cone.closeSubpath()
      self.fill(context, RGB(0.92, 0.74, 0.46))
      context.addPath(cone)
      context.fillPath()
      self.fill(context, color.lightened(0.3))
      context.fillEllipse(in: CGRect(x: center.x - 110, y: center.y - 190, width: 220, height: 220))
    case .card, .ticket, .book:
      self.drawCard(context, center: center, color: color, isTall: shape == .book)
    case .burger:
      let bun = RGB(0.90, 0.66, 0.36)
      self.fill(context, bun)
      context.fillEllipse(in: CGRect(x: center.x - 170, y: center.y - 150, width: 340, height: 180))
      self.fill(context, RGB(0.40, 0.70, 0.34))
      context.fill(CGRect(x: center.x - 180, y: center.y - 10, width: 360, height: 30))
      self.fill(context, RGB(0.50, 0.30, 0.22))
      context.fill(CGRect(x: center.x - 170, y: center.y + 20, width: 340, height: 60))
      self.fill(context, bun)
      context.fill(CGRect(x: center.x - 170, y: center.y + 80, width: 340, height: 60))
    }
  }

  private static func drawCup(_ context: CGContext, center: CGPoint, color: RGB, hasStraw: Bool) {
    let cup = CGMutablePath()
    cup.move(to: CGPoint(x: center.x - 110, y: center.y - 130))
    cup.addLine(to: CGPoint(x: center.x + 110, y: center.y - 130))
    cup.addLine(to: CGPoint(x: center.x + 80, y: center.y + 170))
    cup.addLine(to: CGPoint(x: center.x - 80, y: center.y + 170))
    cup.closeSubpath()
    self.fill(context, hasStraw ? RGB(0.98, 0.62, 0.30) : RGB(0.55, 0.36, 0.26))
    context.addPath(cup)
    context.fillPath()
    self.fill(context, color)
    context.fill(CGRect(x: center.x - 125, y: center.y - 170, width: 250, height: 44))
    if hasStraw {
      context.fill(CGRect(x: center.x + 20, y: center.y - 260, width: 16, height: 100))
    }
  }

  private static func drawCard(_ context: CGContext, center: CGPoint, color: RGB, isTall: Bool) {
    let size = isTall ? CGSize(width: 240, height: 320) : CGSize(width: 360, height: 220)
    let rect = CGRect(
      x: center.x - size.width / 2,
      y: center.y - size.height / 2,
      width: size.width,
      height: size.height
    )
    self.fill(context, color)
    self.fillRounded(context, rect, radius: 24)
    self.fill(context, .white, alpha: 0.7)
    context.fill(CGRect(x: rect.minX + 40, y: center.y - 20, width: size.width - 80, height: 16))
    context.fill(CGRect(x: rect.minX + 40, y: center.y + 20, width: size.width * 0.4, height: 16))
  }

  private static func fillRounded(_ context: CGContext, _ rect: CGRect, radius: CGFloat) {
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
  }

  /// 번호 글자로 정한 줄무늬. 앱은 인식 결과의 값으로 바코드를 다시 그리므로 이 줄무늬는 읽히지 않아도 된다.
  private static func drawBars(_ context: CGContext, in rect: CGRect, seed: String) {
    self.fill(context, .black)
    let widths = seed.unicodeScalars.map { Int($0.value) % 4 + 1 }
    var x = rect.minX
    var index = 0
    while x < rect.maxX - 4 {
      let barWidth = CGFloat(widths[index % max(widths.count, 1)]) * 3
      if index.isMultiple(of: 2) {
        context.fill(CGRect(x: x, y: rect.minY, width: barWidth, height: rect.height))
      }
      x += barWidth
      index += 1
    }
  }
}
