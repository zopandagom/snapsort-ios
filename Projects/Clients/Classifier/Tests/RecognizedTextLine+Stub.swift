import Core
import CoreGraphics

extension RecognizedTextLine {
  static func line(_ text: String) -> RecognizedTextLine {
    RecognizedTextLine(text: text, confidence: 0.9, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.1))
  }
}
