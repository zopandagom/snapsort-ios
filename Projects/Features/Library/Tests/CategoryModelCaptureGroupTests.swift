import Core
import Foundation
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 쇼핑·대화·지도 카테고리 화면의 읽기. `captureGroupItems(in:)` 로 읽고, 월별과 묶기별 섹션을 같은 읽기에서 만든다.
/// 읽기를 붙잡을 때는 `onCaptureGroupItems` 에 `CallGates` 를, 실패는 `captureGroupItemsErrors` 를 쓴다.
@MainActor
struct CategoryModelCaptureGroupTests {
  @Test("쇼핑을 열면 captureGroupItems 로 읽어 월별·쇼핑몰별·브랜드별 섹션을 함께 만든다")
  func shoppingBuildsMonthsAndGroupsFromOneRead() async {
    let photoStore = PhotoStoreClientFake(images: [
      .captured(id: "coupang-nike", .seoul(2026, 10, 3, hour: 12), groups: .test(mall: "coupang", brand: "nike")),
      .captured(id: "musinsa", .seoul(2026, 9, 3, hour: 12), groups: .test(mall: "musinsa")),
      .captured(id: "unknown", .seoul(2026, 9, 2, hour: 12), groups: .empty),
      .captured(id: "waiting", .seoul(2026, 9, 1, hour: 12), groups: nil),
      .dated(id: "person", .seoul(2026, 10, 1, hour: 12)),
    ])
    let model = CategoryModel.fixture(photoStore: photoStore)

    let appear = Task { await model.onAppear(category: .shopping) }
    await waitUntil { model.content != .loading }

    #expect(model.content.sectionIDs == [["coupang-nike"], ["musinsa", "unknown", "waiting"]])
    #expect(model.content.groupSectionIDs(.mall) == [["coupang-nike"], ["musinsa"], ["unknown"], ["waiting"]])
    #expect(model.content.groupSectionKinds(.mall) == [
      .group(.mall(.test("coupang"))), .group(.mall(.test("musinsa"))), .unknown, .checking,
    ])
    #expect(model.content.groupSectionIDs(.brand) == [["coupang-nike"], ["musinsa", "unknown"], ["waiting"]])
    #expect(model.content.groupSectionKinds(.brand) == [.group(.brand(.test("nike"))), .unknown, .checking])
    #expect(model.content.groupSectionIDs(.region) == nil)
    #expect(photoStore.captureGroupItemsCallCount == 1)
    #expect(photoStore.assetsCallCount == 0)

    await cancelAndWait(appear)
  }

  @Test("대화는 앱별, 지도는 지역별 섹션을 만든다")
  func chatAndMapBuildTheirGroupings() async {
    let photoStore = PhotoStoreClientFake(images: [
      .captured(
        id: "kakao",
        .seoul(2026, 10, 3, hour: 12),
        category: .chat,
        groups: CaptureGroups(chatApp: .kakaoTalk)
      ),
      .captured(
        id: "two-regions",
        .seoul(2026, 10, 2, hour: 12),
        category: .map,
        groups: .test(regions: ["seoul:강남구", "busan:해운대구"])
      ),
    ])
    let model = CategoryModel.fixture(photoStore: photoStore)

    let chat = Task { await model.onAppear(category: .chat) }
    await waitUntil { model.content != .loading }
    #expect(model.content.groupSectionIDs(.chatApp) == [["kakao"]])
    #expect(model.content.groupSectionIDs(.region) == nil)
    await cancelAndWait(chat)

    let map = Task { await model.onAppear(category: .map) }
    await waitUntil { model.category == .map && model.content != .loading }
    // 한 장이 두 지역 섹션에 모두 든다.
    #expect(model.content.groupSectionIDs(.region) == [["two-regions"], ["two-regions"]])
    #expect(model.content.sectionIDs == [["two-regions"]])
    await cancelAndWait(map)
  }

  @Test("묶기가 없는 카테고리는 지금처럼 assets(in:) 로 읽고 묶기 섹션이 없다")
  func documentReadsAssetsWithoutGroups() async {
    let photoStore = PhotoStoreClientFake(images: [.dated(id: "doc", nil, categories: [.document])])
    let model = CategoryModel.fixture(photoStore: photoStore)

    let appear = Task { await model.onAppear(category: .document) }
    await waitUntil { model.content != .loading }

    #expect(model.content.sectionIDs == [["doc"]])
    #expect(model.content.groupSectionIDs(.mall) == nil)
    #expect(photoStore.assetsCallCount == 1)
    #expect(photoStore.captureGroupItemsCallCount == 0)

    await cancelAndWait(appear)
  }

  @Test("저장소 변경 신호(소급 끝)로 다시 읽으면 확인 중 항목이 몰 섹션으로 옮겨 간다")
  func reloadMovesCheckingItemToMallSection() async {
    let photoStore = PhotoStoreClientFake(images: [
      .captured(id: "a", .seoul(2026, 10, 3, hour: 12), groups: nil),
    ])
    let model = CategoryModel.fixture(photoStore: photoStore)
    let appear = Task { await model.onAppear(category: .shopping) }
    await waitUntil { model.content.groupSectionKinds(.mall) == [.checking] }

    try? await photoStore.saveCaptureGroups(["a": .test(mall: "coupang")])
    model.libraryStoreChanged()

    await waitUntil { model.content.groupSectionKinds(.mall) == [.group(.mall(.test("coupang")))] }

    await cancelAndWait(appear)
  }

  @Test("다시 읽는 중 온 신호 여럿은 끝난 뒤 한 번으로 합친다")
  func changesDuringReloadCoalesce() async {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(
      images: [.captured(id: "a", nil, groups: .empty)],
      onCaptureGroupItems: { await gates.pass($0) }
    )
    let model = CategoryModel.fixture(photoStore: photoStore)
    let appear = Task { await model.onAppear(category: .shopping) }
    await waitUntil { model.content.sectionIDs == [["a"]] }

    model.libraryStoreChanged()
    await waitUntil { gates.hasEntered(1) }
    model.libraryStoreChanged()
    model.libraryStoreChanged()
    model.libraryStoreChanged()
    gates.open(1)

    // 처음 읽기, 신호로 한 번, 합친 신호로 한 번.
    await waitUntil { photoStore.captureGroupItemsCallCount == 3 }
    await settle()
    #expect(photoStore.captureGroupItemsCallCount == 3)

    await cancelAndWait(appear)
  }

  @Test("화면을 닫은 뒤 늦게 끝난 captureGroupItems 는 내용을 바꾸지 않는다")
  func lateReadAfterCloseIsDropped() async {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let photoStore = PhotoStoreClientFake(
      images: [.captured(id: "a", nil, groups: .empty)],
      onCaptureGroupItems: { await gates.pass($0) }
    )
    let model = CategoryModel.fixture(photoStore: photoStore)
    let appear = Task { await model.onAppear(category: .shopping) }
    await waitUntil { gates.hasEntered(0) }

    appear.cancel()
    gates.open(0)
    await appear.value

    #expect(model.content == .loading)
  }

  @Test("다른 카테고리를 연 뒤 늦게 끝난 지난 captureGroupItems 는 버린다")
  func lateReadFromPreviousCategoryIsDropped() async {
    let gates = CallGates(holding: [0])
    let photoStore = PhotoStoreClientFake(
      images: [
        .captured(id: "shop", nil, groups: .empty),
        .captured(id: "chat", nil, category: .chat, groups: .empty),
      ],
      onCaptureGroupItems: { await gates.pass($0) }
    )
    let model = CategoryModel.fixture(photoStore: photoStore)
    // 지난 화면의 Task 가 아직 취소되지 않은 채로 다음 화면이 열린 경우다.
    let previous = Task { await model.onAppear(category: .shopping) }
    await waitUntil { gates.hasEntered(0) }
    let current = Task { await model.onAppear(category: .chat) }
    await waitUntil { model.content.sectionIDs == [["chat"]] }

    gates.open(0)
    await settle()

    #expect(model.category == .chat)
    #expect(model.content.sectionIDs == [["chat"]])
    await cancelAndWait(previous)
    await cancelAndWait(current)
  }

  @Test("처음 읽기에 실패하면 실패이고 다시 시도하면 읽고, 다시 읽기에 실패하면 지난 섹션을 둔다")
  func failureShowsFailedThenKeepsSectionsOnReloadFailure() async {
    // 호출 0 은 실패, 1 은 성공, 2 는 실패, 3 은 붙잡는다(실패 처리 뒤의 상태를 본다).
    let gates = CallGates(holding: [3])
    let photoStore = PhotoStoreClientFake(
      images: [.captured(id: "a", nil, groups: .empty)],
      captureGroupItemsErrors: [0: .failed, 2: .failed],
      onCaptureGroupItems: { await gates.pass($0) }
    )
    let model = CategoryModel.fixture(photoStore: photoStore)
    let appear = Task { await model.onAppear(category: .shopping) }
    await waitUntil { model.content == .failed }

    model.retryButtonTapped()
    await waitUntil { model.content.sectionIDs == [["a"]] }

    model.libraryStoreChanged()
    await waitUntil { photoStore.captureGroupItemsCallCount == 3 }
    model.libraryStoreChanged()
    await waitUntil { gates.hasEntered(3) }
    #expect(model.content.sectionIDs == [["a"]])

    gates.open(3)
    await cancelAndWait(appear)
  }

  @Test("다시 읽어도 같으면(월·묶기 모두) 내용을 바꾸지 않는다")
  func unchangedReloadKeepsContent() async {
    // 두 번째 읽기를 처리한 뒤에야 세 번째 읽기가 시작되므로, 세 번째를 붙잡아 두 번째 처리가 끝났음을 안다.
    let gates = CallGates(holding: [2])
    let photoStore = PhotoStoreClientFake(
      images: [.captured(id: "a", nil, groups: .test(mall: "coupang"))],
      onCaptureGroupItems: { await gates.pass($0) }
    )
    let model = CategoryModel.fixture(photoStore: photoStore)
    let appear = Task { await model.onAppear(category: .shopping) }
    await waitUntil { model.content.sectionIDs == [["a"]] }
    let changes = CallCounter()
    withObservationTracking {
      _ = model.content
    } onChange: {
      _ = changes.next()
    }

    model.libraryStoreChanged()
    await waitUntil { photoStore.captureGroupItemsCallCount == 2 }
    model.libraryStoreChanged()
    await waitUntil { gates.hasEntered(2) }

    #expect(changes.next() == 0)

    gates.open(2)
    await cancelAndWait(appear)
  }

  @Test("월은 같고 묶음만 바뀐 다시 읽기는 내용을 바꾼다")
  func groupOnlyChangeUpdatesContent() async {
    let photoStore = PhotoStoreClientFake(images: [.captured(id: "a", nil, groups: nil)])
    let model = CategoryModel.fixture(photoStore: photoStore)
    let appear = Task { await model.onAppear(category: .shopping) }
    await waitUntil { model.content.groupSectionKinds(.mall) == [.checking] }
    let monthsBefore = model.content.sectionIDs

    try? await photoStore.saveCaptureGroups(["a": .test(mall: "musinsa")])
    model.libraryStoreChanged()
    await waitUntil { model.content.groupSectionKinds(.mall) == [.group(.mall(.test("musinsa")))] }

    #expect(model.content.sectionIDs == monthsBefore)
    await cancelAndWait(appear)
  }
}

extension ShoppingMall {
  static func test(_ id: String) -> ShoppingMall {
    guard let mall = ShoppingMall(id: id) else { preconditionFailure("없는 몰 id") }
    return mall
  }
}

extension ShoppingBrand {
  static func test(_ id: String) -> ShoppingBrand {
    guard let brand = ShoppingBrand(id: id) else { preconditionFailure("없는 브랜드 id") }
    return brand
  }
}

extension CaptureGroups {
  /// 닫힌 목록의 식별자로 만든 묶음 값.
  static func test(mall: String? = nil, brand: String? = nil, regions: [String] = []) -> CaptureGroups {
    CaptureGroups(
      mall: mall.map(ShoppingMall.test),
      brand: brand.map(ShoppingBrand.test),
      regions: Set(regions.map { id in
        guard let region = KoreanRegion(id: id) else { preconditionFailure("없는 지역 id") }
        return region
      })
    )
  }
}

extension IndexedImage {
  /// 쇼핑·대화·지도로 분류된 캡처. `groups` 가 nil 이면 글자를 읽었지만 추출 대기, 값이 있으면 추출한 것이다.
  static func captured(
    id: String,
    _ creationDate: Date?,
    category: ImageCategory = .shopping,
    groups: CaptureGroups?
  ) -> IndexedImage {
    IndexedImage(
      asset: .stub(id: id, creationDate: creationDate),
      labels: [],
      textRecognition: .recognized([RecognizedTextLine(text: "캡처", confidence: 1, boundingBox: .zero)]),
      categories: [category],
      captureGroups: groups
    )
  }
}

extension CategoryContent {
  private func groupSections(_ grouping: CaptureGrouping) -> [CaptureGroupSection]? {
    guard case let .loaded(sections) = self else { return nil }
    return sections.groups[grouping]
  }

  /// 묶기의 섹션마다 식별자. 읽기 전이거나 그 카테고리에 없는 묶기면 nil.
  func groupSectionIDs(_ grouping: CaptureGrouping) -> [[ImageAsset.ID]]? {
    self.groupSections(grouping)?.map { $0.assets.map(\.id) }
  }

  func groupSectionKinds(_ grouping: CaptureGrouping) -> [CaptureGroupSection.Kind]? {
    self.groupSections(grouping)?.map(\.kind)
  }
}
