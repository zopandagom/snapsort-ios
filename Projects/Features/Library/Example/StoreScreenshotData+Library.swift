import Core
import CoreGraphics
import Foundation
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting

/// 스토어 시나리오의 보관함 나머지: 카테고리별 사진·캡처, 세 여행, 검색 글자 사진, 정리 도우미의 비슷한 사진·최근 스크린샷.
/// 카메라 사진은 모두 서로 먼 벡터를 달아 정리 화면에 "아직 비교하지 않은" 안내가 뜨지 않게 하고, 비슷한 사진 두 묶음만 가까운 벡터다.
extension StoreScreenshotData {
  /// 그림 하나를 여러 장이 나눠 쓴다(같은 카테고리 안 변형 수).
  static let variantCount = 6

  /// 카테고리별 카메라 사진 수(비슷한 사진·여행 사진 제외).
  static let photoCounts: [(ImageCategory, Int)] = [
    (.food, 34),
    (.people, 96),
    (.pet, 23),
    (.landscape, 38),
    (.other, 8),
  ]

  // MARK: - 여행

  struct TripDemo {
    let key: String
    let center: Coordinate
    let start: Date
    let end: Date
    let photoCount: Int
    let placeName: String
  }

  /// 0번 성산(4번 화면이 연다), 1번 경주, 2번 강릉. 세 여행 모두 장소 이름이 캐시돼 있어 지오코딩을 기다리지 않는다.
  static let trips: [TripDemo] = [
    TripDemo(
      key: "seongsan",
      center: Coordinate(latitude: 33.4581, longitude: 126.9425),
      start: StoreScreenshotData.date(2026, 10, 17, hour: 9),
      end: StoreScreenshotData.date(
        2026,
        10,
        19,
        hour: 18
      ),
      photoCount: 12,
      placeName: "제주특별자치도 서귀포시"
    ),
    TripDemo(
      key: "gyeongju",
      center: Coordinate(latitude: 35.8347, longitude: 129.2190),
      start: StoreScreenshotData.date(2026, 9, 20, hour: 10),
      end: StoreScreenshotData.date(
        2026,
        9,
        21,
        hour: 17
      ),
      photoCount: 8,
      placeName: "경상북도 경주시"
    ),
    TripDemo(
      key: "gangneung",
      center: Coordinate(latitude: 37.7956, longitude: 128.8960),
      start: StoreScreenshotData.date(2026, 8, 8, hour: 11),
      end: StoreScreenshotData.date(2026, 8, 9, hour: 16),
      photoCount: 6,
      placeName: "강원특별자치도 강릉시"
    ),
  ]

  /// 4번 화면이 여는 여행 번호. 지도에 상호 POI 가 보이면 1(경주)·2(강릉) 순으로 바꿔 다시 찍는다.
  static let shownTripIndex = 0

  static func tripPhotoID(_ trip: Int, _ index: Int) -> ImageAsset.ID {
    "store-trip-\(self.trips[trip].key)-\(index)"
  }

  static var tripValues: [Trip] {
    self.trips.indices.map { index in
      let demo = self.trips[index]
      return Trip(
        assetIDs: (0 ..< demo.photoCount).map { self.tripPhotoID(index, $0) },
        startDate: demo.start,
        endDate: demo.end,
        center: demo.center
      )
    }
  }

  static var places: [RoundedCoordinate: CachedPlace] {
    var places: [RoundedCoordinate: CachedPlace] = [:]
    for demo in self.trips {
      if let key = RoundedCoordinate(demo.center) {
        places[key] = CachedPlace(name: .named(demo.placeName), timeZoneIdentifier: "Asia/Seoul")
      }
    }
    return places
  }

  /// 여행 사진은 기간에 고르게 퍼진다.
  static func tripPhotos() -> [IndexedImage] {
    self.trips.indices.flatMap { tripIndex in
      let demo = self.trips[tripIndex]
      let span = demo.end.timeIntervalSince(demo.start)
      return (0 ..< demo.photoCount).map { index in
        IndexedImage(
          asset: .stub(
            id: self.tripPhotoID(tripIndex, index),
            creationDate: demo.start.addingTimeInterval(span * Double(index) / Double(max(demo.photoCount - 1, 1))),
            coordinate: demo.center
          ),
          labels: [],
          textRecognition: .notNeeded,
          categories: [.landscape]
        )
      }
    }
  }

  // MARK: - 캡처

  /// 카테고리별 캡처: 그림, 읽은 글자 줄, 생성일. 성산 여행 기간의 영수증 둘·지도 하나·문서 하나는 여행 상세에 묶인다.
  struct CaptureDemo {
    let category: ImageCategory
    let art: StoreScreenshotArtwork.Capture
    var lines: [String] = []
    let creationDate: Date
    var receipt: ReceiptInfo?
    var regions: Set<KoreanRegion> = []
  }

  static func receipt(_ store: String, _ items: [(String, Int)], days: Double, at date: Date? = nil) -> CaptureDemo {
    let total = items.reduce(0) { $0 + $1.1 }
    return CaptureDemo(
      category: .receipt,
      art: .receipt(StoreScreenshotArtwork.Receipt(
        store: store,
        items: items.map { StoreScreenshotArtwork.Item(name: $0.0, price: self.won($0.1)) },
        total: self.won(total)
      )),
      lines: [store, "합계 \(self.won(total))"],
      creationDate: date ?? self.ago(days: days, minutes: 140),
      receipt: .preview(store, krw: total)
    )
  }

  static func won(_ amount: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = self.locale
    return (formatter.string(from: NSNumber(value: amount)) ?? "\(amount)") + "원"
  }

  static func note(_ title: String, _ lines: [String], days: Double, at date: Date? = nil) -> CaptureDemo {
    CaptureDemo(
      category: .document,
      art: .note(title: title, lines: lines),
      lines: [title] + lines,
      creationDate: date ?? self.ago(days: days, minutes: 75)
    )
  }

  static let captures: [CaptureDemo] = {
    let seongsan = StoreScreenshotData.trips[0]
    let middle = seongsan.start.addingTimeInterval(seongsan.end.timeIntervalSince(seongsan.start) / 2)
    var captures: [CaptureDemo] = [
      StoreScreenshotData.receipt("바당국수", [("고기국수", 9000), ("김밥", 3000)], days: 0, at: middle),
      StoreScreenshotData.receipt("오름카페", [("감귤 라떼", 6500)], days: 0, at: middle.addingTimeInterval(1800)),
      CaptureDemo(
        category: .map,
        art: .map(0),
        lines: ["제주 해안 산책로"],
        creationDate: middle.addingTimeInterval(3600),
        regions: KoreanRegion(id: "jeju").map { [$0] } ?? []
      ),
      StoreScreenshotData.note(
        "제주 감귤 체험 예약 확인",
        ["10월 18일 오전 10시", "두 명", "장갑 챙기기"],
        days: 0,
        at: middle.addingTimeInterval(-3600)
      ),
    ]
    let receipts: [(String, [(String, Int)])] = [
      ("모퉁이분식", [("라면", 4500), ("김밥", 3500)]), ("햇살마트", [("우유", 2800), ("달걀", 6900), ("사과", 8000)]),
      ("보리빵집", [("식빵", 4200), ("크루아상", 3600)]), ("소나무식당", [("된장찌개", 9000), ("공깃밥", 1000)]),
      ("들꽃카페", [("카페라떼", 5000)]), ("반짝문구", [("공책", 2500), ("볼펜", 1500)]),
      ("언덕베이커리", [("머핀", 3200)]), ("새벽채소", [("상추", 2000), ("오이", 2500)]),
      ("달빛세탁", [("셔츠 세탁", 6000)]), ("골목국밥", [("국밥", 9500)]),
      ("숲속찻집", [("유자차", 5500)]), ("바닷가횟집", [("모둠회", 45000)]),
    ]
    captures += receipts.enumerated().map { index, receipt in
      StoreScreenshotData.receipt(receipt.0, receipt.1, days: Double(index) * 6 + 2)
    }
    captures += [
      StoreScreenshotData.note("제주 돌담길 산책 메모", ["오름 입구에서 출발", "바다 쪽 길로 돌아오기"], days: 3),
      StoreScreenshotData.note("바당국수 제주점", ["고기국수 맛있었음", "다음에 또 오기"], days: 15),
      StoreScreenshotData.note("장보기 목록", ["우유", "달걀", "사과"], days: 1),
      StoreScreenshotData.note("회의 메모", ["다음 주 화요일", "자료 정리해서 공유"], days: 8),
      StoreScreenshotData.note("읽을 책", ["소설 두 권", "여행 에세이"], days: 22),
      StoreScreenshotData.note("운동 기록", ["걷기 40분", "스트레칭"], days: 30),
    ]
    captures += (0 ..< 8)
      .map { CaptureDemo(category: .shopping, art: .shopping($0), creationDate: .storeAgo($0 * 9 + 4)) }
    captures += (0 ..< 11).map { CaptureDemo(category: .chat, art: .chat($0), creationDate: .storeAgo($0 * 7 + 1)) }
    captures += (1 ..< 5).map { CaptureDemo(category: .map, art: .map($0), creationDate: .storeAgo($0 * 13 + 5)) }
    return captures
  }()

  static func captureID(_ index: Int) -> ImageAsset.ID {
    self.id("capture", index)
  }

  static func captureImages() -> [IndexedImage] {
    self.captures.enumerated().map { index, demo in
      IndexedImage(
        asset: .stub(
          id: self.captureID(index),
          creationDate: demo.creationDate,
          pixelWidth: 1320,
          pixelHeight: 2868,
          isScreenshot: true
        ),
        labels: [],
        textRecognition: .recognized(demo.lines
          .map { RecognizedTextLine(text: $0, confidence: 1, boundingBox: .zero) }),
        categories: [demo.category],
        receipt: demo.receipt,
        captureGroups: [.shopping, .chat, .map].contains(demo.category)
          ? CaptureGroups(mall: nil, brand: nil, chatApp: nil, regions: demo.regions)
          : nil
      )
    }
  }

  // MARK: - 카메라 사진·정리

  static func photoID(_ category: ImageCategory, _ index: Int) -> ImageAsset.ID {
    self.id(category.rawValue, index)
  }

  static func photoImages() -> [IndexedImage] {
    self.photoCounts.enumerated().flatMap { categoryIndex, entry in
      (0 ..< entry.1).map { index in
        IndexedImage(
          asset: .stub(
            id: self.photoID(entry.0, index),
            creationDate: self.ago(days: Double(index) * 3.3 + 0.5, minutes: Double(categoryIndex * 97 + 11))
          ),
          labels: [],
          textRecognition: .notNeeded,
          categories: [entry.0]
        )
      }
    }
  }

  /// 비슷한 사진 두 묶음: 풍경 3장(사흘 전, 2초 간격)·반려동물 4장(아흐레 전, 2초 간격). 이웃 거리 0.05.
  struct SimilarGroup {
    let category: ImageCategory
    let count: Int
    let daysAgo: Double
    /// 첫 장 벡터 값. 다음 장마다 0.05 씩 멀어진다.
    let base: Float
  }

  static let similarGroups = [
    SimilarGroup(category: .landscape, count: 3, daysAgo: 3, base: 0),
    SimilarGroup(category: .pet, count: 4, daysAgo: 9, base: 3),
  ]

  static func similarID(_ group: Int, _ index: Int) -> ImageAsset.ID {
    "store-similar-\(group)-\(index)"
  }

  static func similarImages() -> [IndexedImage] {
    self.similarGroups.enumerated().flatMap { groupIndex, group in
      (0 ..< group.count).map { index in
        IndexedImage(
          asset: .stub(
            id: self.similarID(groupIndex, index),
            creationDate: self.ago(days: group.daysAgo, minutes: 200).addingTimeInterval(Double(index) * 2)
          ),
          labels: [],
          textRecognition: .notNeeded,
          categories: [group.category],
          featurePrint: self.featurePrint(group.base + Float(index) * 0.05)
        )
      }
    }
  }

  /// 최근 스크린샷 화면의 "기타" 스크린샷(30일 안).
  static let recentShotDaysAgo: [Double] = [0.2, 2, 6, 13]

  static func recentShots() -> [IndexedImage] {
    self.recentShotDaysAgo.enumerated().map { index, days in
      IndexedImage(
        asset: .stub(id: self.id("shot", index), creationDate: self.ago(days: days, minutes: 20), isScreenshot: true),
        labels: [],
        textRecognition: .notNeeded,
        categories: [.other]
      )
    }
  }

  /// 첫 원소만 `value` 인 벡터. 두 벡터의 거리는 첫 원소 차이다.
  static func featurePrint(_ value: Float) -> ImageFeaturePrint? {
    var values = [Float](repeating: 0, count: ImageFeaturePrint.elementCount)
    values[0] = value
    return ImageFeaturePrint(values: values)
  }

  /// 비슷한 사진 묶음이 아닌 카메라 사진에 서로 먼 벡터를 단다(정리 화면의 미비교 안내를 없앤다).
  static func withDistantFeaturePrints(_ images: [IndexedImage]) -> [IndexedImage] {
    images.enumerated().map { index, image in
      IndexedImage(
        asset: image.asset,
        labels: image.labels,
        textRecognition: image.textRecognition,
        categories: image.categories,
        featurePrint: self.featurePrint(100 + Float(index) * 10)
      )
    }
  }
}

extension Date {
  /// 스토어 시나리오의 고정 "지금"에서 며칠 전(캡처 생성일).
  static func storeAgo(_ days: Int) -> Date {
    StoreScreenshotData.ago(days: Double(days), minutes: 50)
  }
}
