import Core
import Foundation
import PhotoStoreInterface

/// Example 의 영수증 데모. 가게·금액은 지어낸 값이다. 날짜는 실행일과 무관한 2026 고정 시각이고, 매달 15일 낮이라
/// 시뮬레이터 시간대가 어디든 같은 달에 든다. 여행 영수증(`PreviewTrips.receiptValues`)과 달이 겹치지 않는다.
/// 한 화면에서 정상·통화 섞임·확인 중(OCR 대기·추출 대기)·취소·가게 모름·금액 모름·날짜 없음을 본다.
enum PreviewReceipts {
  struct Demo {
    let creationDate: Date?
    let info: ReceiptInfo?
    var status: Status = .extracted
  }

  enum Status {
    case extracted
    /// 글자를 아직 읽지 않았다(OCR 대기).
    case waitingForText
    /// 글자를 읽었고 추출 대기다.
    case waitingForExtraction
  }

  /// 줄 순서가 식별자 번호다(`PreviewPhotos.id(.receipt, index)`).
  static let demos: [Demo] = [
    Demo(creationDate: .previewSeoul(2026, 10, 15, hour: 12), info: .preview("스타벅스 강남점", krw: 9000)),
    Demo(creationDate: .previewSeoul(2026, 10, 15, hour: 11), info: .preview("스타벅스 강남점", krw: 4500)),
    Demo(
      creationDate: .previewSeoul(2026, 10, 15, hour: 10),
      info: .preview("스타벅스 강남점", krw: 9000, isCancelled: true)
    ),
    Demo(creationDate: .previewSeoul(2026, 10, 15, hour: 9), info: nil, status: .waitingForText),
    Demo(creationDate: .previewSeoul(2026, 9, 15, hour: 12), info: .preview("(주)예시마트", krw: 52300)),
    // 법인 표기만 달라 위 줄과 같은 가게로 묶인다.
    Demo(creationDate: .previewSeoul(2026, 9, 15, hour: 11), info: .preview("예시마트", krw: 18000)),
    Demo(
      creationDate: .previewSeoul(2026, 9, 15, hour: 10),
      info: .preview("WHOLE FOODS MARKET", minorUnits: 4520, currency: .usd)
    ),
    Demo(creationDate: .previewSeoul(2026, 9, 15, hour: 9), info: .preview(nil, krw: 12000)),
    Demo(creationDate: .previewSeoul(2026, 6, 15, hour: 12), info: ReceiptInfo(
      storeName: "카페 예시",
      amount: nil,
      isCancelled: false
    )),
    Demo(
      creationDate: .previewSeoul(2026, 6, 15, hour: 11),
      info: .preview("ローソン 渋谷店", minorUnits: 1234, currency: .jpy)
    ),
    // "영수증 추출" 버튼이 "예시 베이커리 ₩6,500" 으로 채운다.
    Demo(creationDate: .previewSeoul(2026, 6, 15, hour: 10), info: nil, status: .waitingForExtraction),
    Demo(creationDate: nil, info: .preview("예시분식", krw: 8000)),
  ]

  /// "영수증 추출" 버튼이 소급 추출처럼 쓸 값. 추출 대기 행만 바뀌므로(Fake `saveReceipts`) OCR 대기 행은 확인 중으로 남는다.
  /// 모두 확인 중인 시나리오(`receiptChecking`)에서는 추출 대기 행이 아래 표의 값으로 바뀐다.
  static var extractedValues: [ImageAsset.ID: ReceiptInfo] {
    var values: [ImageAsset.ID: ReceiptInfo] = [:]
    for (index, demo) in self.demos.enumerated() {
      values[PreviewPhotos.id(.receipt, index)] = demo.info ?? .preview("예시 베이커리", krw: 6500)
    }
    values.merge(PreviewTrips.receiptValues) { demo, _ in demo }
    return values
  }

  /// 데모 영수증. `allChecking` 이면 모두 확인 중이다(짝수 번은 OCR 대기, 홀수 번은 추출 대기).
  static func images(allChecking: Bool) -> [IndexedImage] {
    self.demos.enumerated().map { index, demo in
      let asset = ImageAsset.stub(id: PreviewPhotos.id(.receipt, index), creationDate: demo.creationDate)
      let status: Status = if allChecking {
        index.isMultiple(of: 2) ? .waitingForText : .waitingForExtraction
      } else {
        demo.status
      }
      switch status {
      case .waitingForText:
        return IndexedImage(asset: asset, labels: [], textRecognition: .pending, categories: [.receipt])
      case .waitingForExtraction:
        return IndexedImage(asset: asset, labels: [], textRecognition: .recognized(self.lines), categories: [.receipt])
      case .extracted:
        return IndexedImage(
          asset: asset,
          labels: [],
          textRecognition: .recognized(self.lines),
          categories: [.receipt],
          receipt: demo.info
        )
      }
    }
  }

  /// 데모 영수증이 읽은 것으로 둘 OCR 줄. Fake 는 줄로 추출하지 않으므로 값과 맞추지 않는다.
  static let lines = ["영수증", "합계"].map { RecognizedTextLine(text: $0, confidence: 1, boundingBox: .zero) }
}

extension ReceiptInfo {
  static func preview(_ storeName: String?, krw: Int, isCancelled: Bool = false) -> ReceiptInfo {
    .preview(storeName, minorUnits: krw, currency: .krw, isCancelled: isCancelled)
  }

  static func preview(
    _ storeName: String?,
    minorUnits: Int,
    currency: ReceiptCurrency,
    isCancelled: Bool = false
  ) -> ReceiptInfo {
    ReceiptInfo(
      storeName: storeName,
      amount: ReceiptAmount(minorUnits: minorUnits, currency: currency),
      isCancelled: isCancelled
    )
  }
}
