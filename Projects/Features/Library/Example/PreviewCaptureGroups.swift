import Core
import Foundation
import PhotoStoreInterface

/// Example 의 쇼핑·대화·지도 묶기 데모. 몰·브랜드·앱·지역은 닫힌 목록의 값이고 이미지는 지어낸 것이다.
/// 날짜는 실행일과 무관한 2026 고정 시각이고, 매달 15일 낮이라 시뮬레이터 시간대가 어디든 같은 달에 든다.
/// 한 화면에서 정상·한 항목 여러 지역·값 모름·확인 중(OCR 대기·추출 대기)을 본다.
enum PreviewCaptureGroups {
  struct Demo {
    let creationDate: Date?
    /// 추출한 값. 추출 대기 행에서는 "캡처 묶음 추출" 버튼이 쓸 값이고, OCR 대기 행은 nil 이다.
    let groups: CaptureGroups?
    var status: Status = .extracted
  }

  enum Status {
    case extracted
    /// 글자를 아직 읽지 않았다(OCR 대기).
    case waitingForText
    /// 글자를 읽었고 추출 대기다.
    case waitingForExtraction
  }

  /// 데모를 보이는 카테고리.
  static let categories: [ImageCategory] = [.shopping, .chat, .map]

  /// 줄 순서가 식별자 번호다(`PreviewPhotos.id(category, index)`).
  static let shopping: [Demo] = [
    Demo(creationDate: .previewSeoul(2026, 10, 15, hour: 12), groups: .preview(mall: "coupang", brand: "nike")),
    Demo(creationDate: .previewSeoul(2026, 10, 15, hour: 11), groups: .preview(mall: "coupang")),
    Demo(creationDate: .previewSeoul(2026, 9, 15, hour: 12), groups: .preview(mall: "musinsa", brand: "adidas")),
    Demo(creationDate: .previewSeoul(2026, 9, 15, hour: 11), groups: .preview(brand: "nike")),
    Demo(creationDate: .previewSeoul(2026, 9, 15, hour: 10), groups: nil, status: .waitingForText),
    // "캡처 묶음 추출" 버튼이 올리브영으로 채운다.
    Demo(
      creationDate: .previewSeoul(2026, 8, 15, hour: 12),
      groups: .preview(mall: "oliveYoung"),
      status: .waitingForExtraction
    ),
    Demo(creationDate: nil, groups: .preview(mall: "musinsa")),
  ]

  static let chat: [Demo] = [
    Demo(creationDate: .previewSeoul(2026, 10, 15, hour: 12), groups: .preview(chatApp: .kakaoTalk)),
    Demo(creationDate: .previewSeoul(2026, 10, 15, hour: 11), groups: .preview(chatApp: .kakaoTalk)),
    Demo(creationDate: .previewSeoul(2026, 9, 15, hour: 12), groups: .preview(chatApp: .messages)),
    Demo(creationDate: .previewSeoul(2026, 9, 15, hour: 11), groups: .empty),
    Demo(creationDate: .previewSeoul(2026, 9, 15, hour: 10), groups: nil, status: .waitingForText),
    // "캡처 묶음 추출" 버튼이 메시지로 채운다.
    Demo(
      creationDate: .previewSeoul(2026, 8, 15, hour: 12),
      groups: .preview(chatApp: .messages),
      status: .waitingForExtraction
    ),
  ]

  static let map: [Demo] = [
    Demo(creationDate: .previewSeoul(2026, 10, 15, hour: 12), groups: .preview(regions: ["seoul:강남구"])),
    // 한 장에 두 지역이 보인다. 두 지역 섹션에 모두 든다.
    Demo(
      creationDate: .previewSeoul(2026, 10, 15, hour: 11),
      groups: .preview(regions: ["seoul:강남구", "busan:해운대구"])
    ),
    Demo(creationDate: .previewSeoul(2026, 9, 15, hour: 12), groups: .preview(regions: ["jeju"])),
    Demo(creationDate: .previewSeoul(2026, 9, 15, hour: 11), groups: .empty),
    Demo(creationDate: .previewSeoul(2026, 9, 15, hour: 10), groups: nil, status: .waitingForText),
    // "캡처 묶음 추출" 버튼이 서울 마포구로 채운다.
    Demo(
      creationDate: .previewSeoul(2026, 8, 15, hour: 12),
      groups: .preview(regions: ["seoul:마포구"]),
      status: .waitingForExtraction
    ),
    Demo(creationDate: nil, groups: .preview(regions: ["busan:해운대구"])),
  ]

  static func demos(for category: ImageCategory) -> [Demo] {
    switch category {
    case .shopping: self.shopping
    case .chat: self.chat
    case .map: self.map
    default: []
    }
  }

  /// 카테고리별 데모 수. `PreviewPhotos.counts` 가 쓴다.
  static var counts: [(ImageCategory, Int)] {
    self.categories.map { ($0, self.demos(for: $0).count) }
  }

  /// "캡처 묶음 추출" 버튼이 소급 추출처럼 쓸 값. 추출 대기 행만 바뀌므로(Fake `saveCaptureGroups`) OCR 대기 행은 확인 중으로 남는다.
  static var extractedValues: [ImageAsset.ID: CaptureGroups] {
    var values: [ImageAsset.ID: CaptureGroups] = [:]
    for category in self.categories {
      for (index, demo) in self.demos(for: category).enumerated() {
        if let groups = demo.groups {
          values[PreviewPhotos.id(category, index)] = groups
        }
      }
    }
    return values
  }

  static func images() -> [IndexedImage] {
    self.categories.flatMap { category in
      self.demos(for: category).enumerated().map { index, demo in
        let asset = ImageAsset.stub(id: PreviewPhotos.id(category, index), creationDate: demo.creationDate)
        switch demo.status {
        case .waitingForText:
          return IndexedImage(asset: asset, labels: [], textRecognition: .pending, categories: [category])
        case .waitingForExtraction:
          return IndexedImage(
            asset: asset,
            labels: [],
            textRecognition: .recognized(self.lines),
            categories: [category]
          )
        case .extracted:
          return IndexedImage(
            asset: asset,
            labels: [],
            textRecognition: .recognized(self.lines),
            categories: [category],
            captureGroups: demo.groups
          )
        }
      }
    }
  }

  /// 데모 이미지가 읽은 것으로 둘 OCR 줄. Fake 는 줄로 추출하지 않으므로 값과 맞추지 않는다.
  static let lines = ["캡처"].map { RecognizedTextLine(text: $0, confidence: 1, boundingBox: .zero) }
}

extension CaptureGroups {
  /// 데모 값. 식별자가 닫힌 목록에 없으면 실행 전에 알 수 있게 멈춘다(지어낸 데모 값의 오타).
  static func preview(
    mall: String? = nil,
    brand: String? = nil,
    chatApp: ChatApp? = nil,
    regions: [String] = []
  ) -> CaptureGroups {
    CaptureGroups(
      mall: mall.map { id in
        guard let mall = ShoppingMall(id: id) else { preconditionFailure("없는 몰 id") }
        return mall
      },
      brand: brand.map { id in
        guard let brand = ShoppingBrand(id: id) else { preconditionFailure("없는 브랜드 id") }
        return brand
      },
      chatApp: chatApp,
      regions: Set(regions.map { id in
        guard let region = KoreanRegion(id: id) else { preconditionFailure("없는 지역 id") }
        return region
      })
    )
  }
}
