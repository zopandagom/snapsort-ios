import Core
import CoreGraphics
import Foundation
import Testing

/// `Fixtures/ClassificationSamples.json` 의 샘플로 OCR 대상 판정과 규칙 분류를 함께 확인하는 정확도 회귀 테스트.
/// 샘플은 이미지가 아니라 분류 입력(메타데이터·Vision 라벨·OCR 줄)과 기대 카테고리다. Vision 분류는 시뮬레이터에서 돌지 않으므로
/// 실기기에서 읽은 입력을 기록해 두고, 규칙은 CI 에서 확인한다 (docs/CONVENTIONS.md §3).
/// 샘플은 Debug 기록 도구(SampleRecorderFeature)로 기록한다. 기록한 초안의 `predicted` 를 보고 `expected` 를 채운다.
/// 샘플 형식은 기록 도구의 `SampleDraft`(RecordingOutput.swift)와 짝이다. 한쪽을 바꾸면 다른 쪽도 맞춘다.
/// 기록 도구로 기록하기 전에 직접 만든 시드 샘플(라벨·OCR 줄이 실기기 값이 아니고 라벨은 0.1 이상만)이 함께 있다.
/// 시드 샘플 이름은 `시드 · ` 로 시작하고, 실기기 샘플이 카테고리마다 모이면 지운다.
/// 실기기 샘플 이름은 `실기기 · ` 로 시작하고, OCR 줄은 공백과 분류 키워드(`ClassificationRules` 키워드 표)만 남기고 모든 글자를 `○` 로
/// 가렸다(글자 수는 유지된다). 키워드를 남겨야 기프티콘·영수증처럼 키워드로 정하는 샘플을 확인할 수 있다.
/// 한 줄 전체가 말풍선 시각인 줄은 대화 캡처 판정에 쓰여 그대로 두고, 한 줄 전체가 쿠폰 번호인 줄은 기프티콘 판정에 쓰여 숫자만 `0` 으로 바꾼다. 가리기는 `scripts/mask-samples.py`
/// 로 한다.
struct ClassificationAccuracyTests {
  @Test("샘플 이미지를 기대 카테고리로 분류한다", arguments: ClassificationSample.all)
  func classifiesSample(_ sample: ClassificationSample) {
    let categories = sample.classify()

    // 지울 시점은 샘플마다 `knownIssue` 이유 끝에 있다. 이 래퍼는 지우지 않는다.
    if let knownIssue = sample.knownIssue {
      withKnownIssue(Comment(rawValue: knownIssue)) {
        #expect(categories == sample.expected)
      }
    } else {
      #expect(categories == sample.expected)
    }
  }

  @Test("샘플 파일을 읽는다")
  func loadsSamples() throws {
    #expect(try !ClassificationSample.load().isEmpty)
  }

  @Test("샘플은 규칙 분류기가 낼 수 있는 카테고리만 기대한다")
  func samplesExpectClassifiableCategories() {
    for sample in ClassificationSample.all {
      #expect(!sample.expected.isEmpty, "\(sample.name)")
      #expect(!sample.expected.contains(.travel), "\(sample.name): 여행은 여행 판정이 정한다")
      #expect(!sample.expected.contains(.other) || sample.expected == [.other], "\(sample.name)")
    }
  }

  @Test("정확도 샘플의 knownIssue 는 지울 시점(` — …에서 지운다`)으로 끝난다")
  func knownIssuesEndWithRemovalPoint() {
    for sample in ClassificationSample.all {
      guard let knownIssue = sample.knownIssue else { continue }
      let removal = knownIssue.split(separator: " — ").last
      #expect(knownIssue.contains(" — ") && removal?.hasSuffix("에서 지운다") == true, "\(sample.name)")
    }
  }

  @Test("신뢰도 기준 미만 라벨은 OCR 대상 판정과 분류에 쓰지 않는다")
  func ignoresLabelsBelowMinimumConfidence() {
    let belowMinimum = ClassificationRules.minimumLabelConfidence - 0.01
    // 위치 있는 음식 사진. 기준 미만 `document` 라벨을 쓰면 OCR 대상이 되어 문서·영수증으로도 분류된다.
    let sample = ClassificationSample(
      name: "기준 미만 라벨",
      asset: .init(isScreenshot: false, hasLocation: true, pixelWidth: 4032, pixelHeight: 3024),
      labels: [
        ImageLabel(identifier: "food", confidence: 0.8),
        ImageLabel(identifier: "document", confidence: belowMinimum),
      ],
      text: ["영수증", "합계 9,000"],
      ocrSkipped: nil,
      expected: [.food],
      knownIssue: nil
    )

    #expect(sample.classify() == [.food])
  }

  @Test("OCR 하지 않고 기록한 샘플은 OCR 대상이 아니다")
  func ocrSkippedSamplesStayOutsideTextRecognition() {
    for sample in ClassificationSample.all where sample.ocrSkipped == true {
      // 판정 규칙이 바뀌어 OCR 대상이 되면 빈 `text` 가 틀린 입력이 된다. 기록 도구의 번호로 기록 모드로 다시 기록해 OCR 줄을 채운다.
      #expect(!sample.needsTextRecognition, "\(sample.name): OCR 대상이 되었으니 번호로 기록 모드로 다시 기록한다")
    }
  }

  @Test("바코드를 찾은 위치 없는 샘플은 음식 라벨만 있어도 OCR 대상이다")
  func barcodeSampleNeedsTextRecognition() throws {
    let json = Data("""
    {
      "name": "바코드",
      "asset": {
        "hasBarcode": true, "hasLocation": false, "isScreenshot": false,
        "pixelHeight": 1280, "pixelWidth": 720
      },
      "labels": [{"identifier": "food", "confidence": 0.8}],
      "text": ["교환처", "유효기간 2026.12.31"],
      "expected": ["food", "gifticon"]
    }
    """.utf8)

    let sample = try JSONDecoder().decode(ClassificationSample.self, from: json)

    #expect(sample.needsTextRecognition)
    #expect(sample.classify().contains(.gifticon))
  }

  @Test("샘플 이름은 겹치지 않는다")
  func sampleNamesAreUnique() {
    let names = ClassificationSample.all.map(\.name)

    #expect(Set(names).count == names.count)
  }
}

/// 이미지 한 장의 분류 입력과 기대 결과. OCR 줄(`text`)은 OCR 대상 판정과 관계없이 기록해 두어, 판정 규칙을 바꿔도 다시 기록하지 않는다.
/// 예외로 기록 도구의 보관함 전체 정확도 모드는 OCR 대상만 OCR 해, 나머지 샘플은 `ocrSkipped` 가 true 이고 `text` 가 비어 있다.
/// 라벨도 같은 이유로 신뢰도 기준보다 낮은 것까지 기록해 두고, 분류할 때 기준으로 거른다.
/// 위치는 좌표 대신 있는지만 남긴다. 바코드는 내용 없이 1단계 바코드 확인에서 찾았을 때만 `hasBarcode: true` 를 남긴다.
struct ClassificationSample: Decodable, Sendable, CustomTestStringConvertible {
  struct Asset: Decodable, Sendable {
    let isScreenshot: Bool
    let hasLocation: Bool
    let pixelWidth: Int
    let pixelHeight: Int
    /// 기록 도구가 바코드 확인 대상(`TextRecognitionPolicy.needsBarcodeCheck`)에서 바코드를 찾았는지. 찾았을 때만 true, 그 밖에는 키가 없다.
    var hasBarcode: Bool?
  }

  let name: String
  let asset: Asset
  let labels: [ImageLabel]
  let text: [String]
  /// OCR 대상이 아니어서 OCR 하지 않고 기록했는지. true 면 `text` 가 비어 있고, OCR 대상이 되면 다시 기록해야 한다.
  let ocrSkipped: Bool?
  let expected: Set<ImageCategory>
  /// 사용자와 합의해 미룬 오분류의 이유와 지울 시점(이유 끝에 ` — <지울 시점>에서 지운다`). 있으면 `withKnownIssue` 로 감싼다
  /// (docs/CONVENTIONS.md §3).
  let knownIssue: String?

  var testDescription: String { self.name }

  /// 인덱서와 같은 순서로 분류한다: 라벨을 신뢰도 기준으로 거르고, OCR 대상이 아니면 OCR 줄 없이 규칙 분류기에 넘긴다.
  /// 기록 도구의 `predicted` 도 같은 계산이다.
  func classify() -> Set<ImageCategory> {
    let textLines = self.needsTextRecognition
      ? self.text.map { RecognizedTextLine(text: $0, confidence: 1, boundingBox: .zero) }
      : []
    return RuleClassifier.classify(asset: self.imageAsset, labels: self.ruleLabels, textLines: textLines)
  }

  /// 운영 기준으로 OCR 대상인지(기록한 바코드 확인 결과까지 본다).
  var needsTextRecognition: Bool {
    TextRecognitionPolicy.needsTextRecognition(
      asset: self.imageAsset,
      labels: self.ruleLabels,
      hasBarcode: self.asset.hasBarcode ?? false
    )
  }

  private var ruleLabels: [ImageLabel] {
    self.labels.filter { $0.confidence >= ClassificationRules.minimumLabelConfidence }
  }

  private var imageAsset: ImageAsset {
    ImageAsset(
      id: self.name,
      creationDate: nil,
      coordinate: self.asset.hasLocation ? Coordinate(latitude: 37.5665, longitude: 126.978) : nil,
      pixelWidth: self.asset.pixelWidth,
      pixelHeight: self.asset.pixelHeight,
      isScreenshot: self.asset.isScreenshot
    )
  }

  /// 테스트 인자로 쓰려고 실패하면 비워 둔다. 읽기 실패는 `loadsSamples` 가 알린다.
  static let all: [ClassificationSample] = (try? load()) ?? []

  static func load() throws -> [ClassificationSample] {
    let url = try #require(Bundle(for: BundleToken.self).url(
      forResource: "ClassificationSamples",
      withExtension: "json"
    ))
    return try JSONDecoder().decode([ClassificationSample].self, from: Data(contentsOf: url))
  }
}

private final class BundleToken {}
