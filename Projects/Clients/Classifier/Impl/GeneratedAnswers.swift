import Core
import FoundationModels

/// 기프티콘 요청의 답 형식. 모델 출력은 이 필드로만 받는다(이미지 속 지시문이 형식을 바꾸지 못한다).
/// `@Guide` 를 바꿔서 같은 줄에서 다른 기프티콘 답이 나올 수 있으면 `GifticonExtractor.modelFillVersion` 을 올린다.
@Generable
struct GifticonFields {
  @Guide(description: "만료일(유효기간 끝) 날짜를 OCR 줄에 적힌 그대로 복사한 텍스트. 만료일이라고 적혀 있지 않으면 nil. 발행일·주문일·선물 받은 날은 만료일이 아니다.")
  var expiryDateText: String?
  @Guide(description: "교환처(상품을 받을 수 있는 매장·브랜드) 이름만 OCR 줄에서 그대로 복사. 상품 이름은 넣지 않는다. 없으면 nil.")
  var redemptionPlace: String?
}

/// 분류 요청에서 고를 수 있는 종류. 정보형 카테고리와 `none` 뿐이다.
@Generable
enum InformationKind {
  case gifticon, receipt, chat, shopping, map, document, none
}

/// 분류 요청의 답 형식. 바꿔도 `GifticonExtractor.modelFillVersion` 을 올리지 않는다(분류 보강은 보강 상태를 남기지 않는다).
@Generable
struct InformationKinds {
  @Guide(description: "OCR 텍스트에 근거가 분명한 종류만. 근거가 없으면 [none].", .maximumCount(2))
  var kinds: [InformationKind]
}

extension GifticonFields {
  /// 앞뒤 공백을 자르고, 비면 답이 없는 것으로 본다. 원문과 대조는 받는 쪽(Core)이 한다.
  var modelAnswer: GifticonModelAnswer {
    GifticonModelAnswer(
      expiryText: Self.trimmed(self.expiryDateText),
      redemptionPlace: Self.trimmed(self.redemptionPlace)
    )
  }

  private static func trimmed(_ text: String?) -> String? {
    guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
      return nil
    }
    return text
  }
}

extension InformationKinds {
  /// `none` 은 버린다.
  var categories: Set<ImageCategory> {
    Set(self.kinds.compactMap(\.category))
  }
}

extension InformationKind {
  var category: ImageCategory? {
    switch self {
    case .gifticon: .gifticon
    case .receipt: .receipt
    case .chat: .chat
    case .shopping: .shopping
    case .map: .map
    case .document: .document
    case .none: nil
    }
  }
}
