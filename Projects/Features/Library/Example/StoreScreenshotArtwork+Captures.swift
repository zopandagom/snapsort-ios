import CoreGraphics
import Foundation

/// 캡처형(세로 스크린샷)과 기프티콘 그림. 특정 메신저·쇼핑몰·지도 앱·쿠폰 발급처의 색·서식·로고를 흉내 내지 않는다.
/// 가게·상품·번호는 모두 지어낸 값이고, 주소·전화·사업자번호·계좌 형식의 글자는 넣지 않는다.
extension StoreScreenshotArtwork {
  enum Capture: Hashable {
    /// 영수증: 가게 이름, 항목 줄(이름·금액), 합계 글자.
    case receipt(Receipt)
    case shopping(Int)
    case chat(Int)
    case map(Int)
    /// 줄 노트: 제목과 메모 줄.
    case note(title: String, lines: [String])
  }

  struct Receipt: Hashable {
    let store: String
    let items: [Item]
    let total: String
  }

  struct Item: Hashable {
    let name: String
    let price: String
  }

  static func capture(_ capture: Capture) -> CGImage {
    self.render(self.captureSize) { context, size in
      switch capture {
      case let .receipt(receipt):
        self.drawReceipt(context, size: size, receipt: receipt)
      case let .shopping(variant):
        self.drawShopping(context, size: size, variant: variant)
      case let .chat(variant):
        self.drawChat(context, size: size, variant: variant)
      case let .map(variant):
        self.drawMap(context, size: size, variant: variant)
      case let .note(title, lines):
        self.drawNote(context, size: size, title: title, lines: lines)
      }
    }
  }

  private static func drawReceipt(_ context: CGContext, size: CGSize, receipt: Receipt) {
    self.fill(context, RGB(0.90, 0.90, 0.92))
    context.fill(CGRect(origin: .zero, size: size))
    // 썸네일(가운데 정사각형)에 가게 이름이 들도록 종이를 아래로 내린다.
    context.translateBy(x: 0, y: 250)
    let paper = CGRect(x: 50, y: 120, width: size.width - 100, height: 760)
    self.fill(context, .white)
    context.fill(paper)
    let center = size.width / 2
    self.drawText(
      context,
      receipt.store,
      TextStyle(size: 40, bold: true),
      at: CGPoint(x: center, y: 170),
      alignment: .center
    )
    self.drawText(context, "영수증", TextStyle(size: 26, color: .gray), at: CGPoint(x: center, y: 230), alignment: .center)
    self.dashedLine(context, from: CGPoint(x: paper.minX + 30, y: 300), length: paper.width - 60)
    for (index, item) in receipt.items.enumerated() {
      let y = 330 + CGFloat(index) * 60
      self.drawText(context, item.name, TextStyle(size: 28), at: CGPoint(x: paper.minX + 30, y: y))
      self.drawText(
        context,
        item.price,
        TextStyle(size: 28),
        at: CGPoint(x: paper.maxX - 30, y: y),
        alignment: .trailing
      )
    }
    let totalY = 330 + CGFloat(receipt.items.count) * 60 + 30
    self.dashedLine(context, from: CGPoint(x: paper.minX + 30, y: totalY), length: paper.width - 60)
    let totalStyle = TextStyle(size: 32, bold: true)
    self.drawText(context, "합계", totalStyle, at: CGPoint(x: paper.minX + 30, y: totalY + 30))
    self.drawText(
      context,
      receipt.total,
      totalStyle,
      at: CGPoint(x: paper.maxX - 30, y: totalY + 30),
      alignment: .trailing
    )
    self.drawText(
      context,
      "감사합니다",
      TextStyle(size: 24, color: .gray),
      at: CGPoint(x: center, y: paper.maxY - 70),
      alignment: .center
    )
  }

  private static func drawShopping(_ context: CGContext, size: CGSize, variant: Int) {
    self.fill(context, RGB(0.98, 0.97, 0.97))
    context.fill(CGRect(origin: .zero, size: size))
    self.fill(context, RGB(0.92, 0.90, 0.91))
    context.fill(CGRect(x: 30, y: 110, width: size.width - 60, height: 60))
    let products: [(String, RGB)] = [
      ("니트 가디건", RGB(0.86, 0.72, 0.62)), ("캔버스 가방", RGB(0.62, 0.72, 0.60)), ("머그컵", RGB(0.70, 0.76, 0.90)),
      ("운동화", RGB(0.94, 0.86, 0.60)), ("목도리", RGB(0.90, 0.62, 0.66)), ("텀블러", RGB(0.66, 0.80, 0.82)),
    ]
    let prices = ["29,000원", "18,500원", "9,900원", "54,000원", "21,000원", "15,800원"]
    let cardWidth = (size.width - 90) / 2
    for index in 0 ..< 4 {
      let product = products[(index + variant) % products.count]
      let x = 30 + CGFloat(index % 2) * (cardWidth + 30)
      let y = 210 + CGFloat(index / 2) * 470
      self.fill(context, product.1)
      context.addPath(CGPath(
        roundedRect: CGRect(x: x, y: y, width: cardWidth, height: cardWidth),
        cornerWidth: 20,
        cornerHeight: 20,
        transform: nil
      ))
      context.fillPath()
      self.fill(context, .white, alpha: 0.6)
      context.fillEllipse(in: CGRect(
        x: x + cardWidth * 0.3,
        y: y + cardWidth * 0.3,
        width: cardWidth * 0.4,
        height: cardWidth * 0.4
      ))
      self.drawText(context, product.0, TextStyle(size: 26), at: CGPoint(x: x + 4, y: y + cardWidth + 16))
      self.drawText(
        context,
        prices[(index + variant) % prices.count],
        TextStyle(size: 28, bold: true),
        at: CGPoint(x: x + 4, y: y + cardWidth + 56)
      )
    }
  }

  private static func drawChat(_ context: CGContext, size: CGSize, variant: Int) {
    self.fill(context, RGB(0.97, 0.96, 0.97))
    context.fill(CGRect(origin: .zero, size: size))
    let messages: [(Bool, String)] = [
      (false, "주말에 시간 괜찮아?"), (true, "응 토요일 좋아"), (false, "그럼 열두 시에 보자"),
      (true, "좋아, 점심 같이 먹자"), (false, "사진 나중에 보내 줄게"), (true, "고마워!"),
      (false, "도착하면 연락해"), (true, "곧 출발해"),
    ]
    var y: CGFloat = 140
    for index in 0 ..< 7 {
      let (isMine, text) = messages[(index + variant) % messages.count]
      let bubbleWidth = CGFloat(text.count) * 26 + 50
      let x = isMine ? size.width - bubbleWidth - 30 : 30
      self.fill(context, isMine ? RGB(0.98, 0.80, 0.85) : RGB(0.88, 0.87, 0.89))
      context.addPath(CGPath(
        roundedRect: CGRect(x: x, y: y, width: bubbleWidth, height: 70),
        cornerWidth: 30,
        cornerHeight: 30,
        transform: nil
      ))
      context.fillPath()
      self.drawText(context, text, TextStyle(size: 26), at: CGPoint(x: x + 25, y: y + 20))
      y += 110
    }
  }

  private static func drawMap(_ context: CGContext, size: CGSize, variant: Int) {
    self.fill(context, RGB(0.93, 0.94, 0.90))
    context.fill(CGRect(origin: .zero, size: size))
    self.fill(context, RGB(0.72, 0.84, 0.94))
    self.wave(
      context,
      size: size,
      baseline: size.height * (0.72 + CGFloat(variant % 2) * 0.06),
      amplitude: 30,
      phase: CGFloat(variant)
    )
    self.fill(context, RGB(0.80, 0.90, 0.76))
    context.fillEllipse(in: CGRect(x: size.width * 0.1, y: size.height * 0.2, width: 200, height: 160))
    context.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.setLineWidth(18)
    for index in 0 ..< 4 {
      let offset = CGFloat((index * 137 + variant * 61) % 400)
      context.move(to: CGPoint(x: 0, y: 200 + offset))
      context.addLine(to: CGPoint(x: size.width, y: 120 + offset * 1.3))
      context.move(to: CGPoint(x: 60 + offset, y: 0))
      context.addLine(to: CGPoint(x: 120 + offset * 0.8, y: size.height))
    }
    context.strokePath()
    self.fill(context, RGB(0.77, 0.16, 0.33))
    let pin = CGPoint(x: size.width * 0.55, y: size.height * 0.42)
    context.fillEllipse(in: CGRect(x: pin.x - 30, y: pin.y - 30, width: 60, height: 60))
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: pin.x - 22, y: pin.y + 16))
    tail.addLine(to: CGPoint(x: pin.x, y: pin.y + 70))
    tail.addLine(to: CGPoint(x: pin.x + 22, y: pin.y + 16))
    tail.closeSubpath()
    context.addPath(tail)
    context.fillPath()
    self.fill(context, .white)
    context.fillEllipse(in: CGRect(x: pin.x - 11, y: pin.y - 11, width: 22, height: 22))
  }

  private static func drawNote(_ context: CGContext, size: CGSize, title: String, lines: [String]) {
    self.fill(context, RGB(1.0, 0.98, 0.90))
    context.fill(CGRect(origin: .zero, size: size))
    context.setStrokeColor(red: 0.85, green: 0.82, blue: 0.70, alpha: 1)
    context.setLineWidth(2)
    for row in 0 ..< 18 {
      let y = 260 + CGFloat(row) * 56
      context.move(to: CGPoint(x: 40, y: y))
      context.addLine(to: CGPoint(x: size.width - 40, y: y))
    }
    context.strokePath()
    self.drawText(context, title, TextStyle(size: 38, bold: true), at: CGPoint(x: 48, y: 150))
    for (index, line) in lines.enumerated() {
      self.drawText(
        context,
        line,
        TextStyle(size: 28, color: RGB(0.30, 0.28, 0.30)),
        at: CGPoint(x: 52, y: 274 + CGFloat(index) * 56)
      )
    }
  }

  static func dashedLine(_ context: CGContext, from start: CGPoint, length: CGFloat) {
    context.saveGState()
    context.setStrokeColor(red: 0.7, green: 0.7, blue: 0.72, alpha: 1)
    context.setLineWidth(2)
    context.setLineDash(phase: 0, lengths: [10, 8])
    context.move(to: start)
    context.addLine(to: CGPoint(x: start.x + length, y: start.y))
    context.strokePath()
    context.restoreGState()
  }
}
