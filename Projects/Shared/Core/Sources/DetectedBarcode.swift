import CoreGraphics

/// 이미지에서 읽은 바코드 하나 (docs/ARCHITECTURE.md §4 캡처 정보 추출). 기프티콘 바코드를 화면에 크게 보이는(다시 그리거나 영역을 확대하는, `BarcodeImageRenderer`)
/// 입력이다.
/// 내용은 기프티콘을 바로 쓸 수 있는 번호이므로 기기 밖으로 보내거나 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
public struct DetectedBarcode: Sendable, Hashable {
  /// 바코드에 담긴 글자. 글자로 읽을 수 없는 바코드(이진 데이터)는 결과에 넣지 않는다.
  public let payload: String
  public let symbology: Symbology
  /// 이미지 안 위치. 이미지를 바르게 돌린 기준으로 0~1 정규화하고, 원점은 왼쪽 위다 (`RecognizedTextLine` 과 같다).
  public let boundingBox: CGRect

  public init(payload: String, symbology: Symbology, boundingBox: CGRect) {
    self.payload = payload
    self.symbology = symbology
    self.boundingBox = boundingBox
  }

  /// 바코드 종류. 다시 그릴 수 있는지 판단하는 데 쓴다.
  /// 기프티콘에 쓰이는 종류와 Core Image 로 다시 그릴 수 있는 종류(QR·Code128·PDF417·Aztec)만 따로 두고 나머지는 `other` 로 묶는다.
  public enum Symbology: Sendable, Hashable {
    case qrCode
    case code128
    case pdf417
    case aztec
    case dataMatrix
    case ean13
    case ean8
    case upce
    case code39
    case itf14
    case other
  }
}
