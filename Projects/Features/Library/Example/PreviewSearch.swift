import Core
import Foundation
import PhotoStoreInterface

/// Example 의 검색 데모. 글자를 읽은 문서 사진과 OCR 대기 사진이고, 줄은 지어낸 것이다.
/// 쇼핑·대화·지도 캡처의 묶음 값(`PreviewCaptureGroups`)과 카테고리 이름, 캐시된 여행 장소 이름(`PreviewTrips`)은 따로 찾힌다.
/// 날짜는 실행일과 무관한 2026 고정 시각이다.
enum PreviewSearch {
  struct Demo {
    let creationDate: Date
    /// nil 이면 글자를 아직 읽지 않았다(OCR 대기).
    let lines: [String]?
  }

  static let demos: [Demo] = [
    Demo(creationDate: .previewSeoul(2026, 10, 14, hour: 12), lines: ["스타벅스 아메리카노", "4,500원", "2026.10.14"]),
    Demo(creationDate: .previewSeoul(2026, 10, 13, hour: 12), lines: ["쿠팡 로켓배송", "나이키 운동화 주문 완료"]),
    Demo(creationDate: .previewSeoul(2026, 10, 12, hour: 12), lines: ["점심 약속", "강남역 2번 출구"]),
    Demo(creationDate: .previewSeoul(2026, 10, 11, hour: 12), lines: nil),
    Demo(creationDate: .previewSeoul(2026, 10, 10, hour: 12), lines: nil),
  ]

  /// 데모 버튼으로 더할 수 있는 글자 사진 수. 읽기 결과를 미리 만들어 둔다.
  static let newImageCapacity = 20

  static func id(_ index: Int) -> ImageAsset.ID {
    "search-\(index)"
  }

  static func newImageID(_ index: Int) -> ImageAsset.ID {
    "search-new-\(index)"
  }

  static var imageIDs: [ImageAsset.ID] {
    self.demos.indices.map { self.id($0) } + (0 ..< self.newImageCapacity).map { self.newImageID($0) }
  }

  static func images() -> [IndexedImage] {
    self.demos.enumerated().map { index, demo in
      IndexedImage(
        asset: .stub(id: self.id(index), creationDate: demo.creationDate),
        labels: [],
        textRecognition: demo.lines.map { TextRecognition.recognized($0.map(Self.line)) } ?? .pending,
        categories: [.document]
      )
    }
  }

  /// "글자 사진 추가" 버튼이 최신으로 더하는 글자 사진.
  static func newImage(id: ImageAsset.ID) -> IndexedImage {
    IndexedImage(
      asset: .stub(id: id, creationDate: Date()),
      labels: [],
      textRecognition: .recognized([self.line("새 영수증 스타벅스")]),
      categories: [.document]
    )
  }

  private static func line(_ text: String) -> RecognizedTextLine {
    RecognizedTextLine(text: text, confidence: 1, boundingBox: .zero)
  }
}
