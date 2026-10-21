import Core
import Foundation
import Observation
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 카테고리 화면의 목록 읽기와 다시 읽기. 읽기를 붙잡을 때는 `onAssets` 에 `CallGates` 를, 실패는 `assetsErrors` 를 쓴다.
@MainActor
struct CategoryModelTests {
  @Test("열면 읽는 동안 불러오는 중이고, 읽으면 월별 섹션이다")
  func showsLoadingThenMonthSections() async {
    let gates = CallGates(holding: [0])
    let photoStore = PhotoStoreClientFake(
      images: [
        .dated(id: "sep", .seoul(2026, 9, 20, hour: 12)),
        .dated(id: "oct-early", .seoul(2026, 10, 1, hour: 9)),
        .dated(id: "undated", nil),
        .dated(id: "oct-late", .seoul(2026, 10, 3, hour: 12)),
        .dated(id: "food", .seoul(2026, 10, 2, hour: 12), categories: [.food]),
      ],
      onAssets: { await gates.pass($0) }
    )
    let model = CategoryModel.fixture(photoStore: photoStore)

    let appear = Task { await model.onAppear(category: .people) }
    await waitUntil { gates.hasEntered(0) }
    #expect(model.category == .people)
    #expect(model.content == .loading)

    gates.open(0)
    await waitUntil { model.content != .loading }
    #expect(model.content.sectionIDs == [["oct-late", "oct-early"], ["sep"], ["undated"]])
    #expect(model.content.sectionMonths == [
      ImageMonth(era: 1, year: 2026, month: 10), ImageMonth(era: 1, year: 2026, month: 9), nil,
    ])

    await cancelAndWait(appear)
  }

  @Test("이미지가 없으면 빈 목록이다")
  func emptyCategoryShowsEmpty() async {
    let photoStore = PhotoStoreClientFake(images: [.dated(id: "food", nil, categories: [.food])])
    let model = CategoryModel.fixture(photoStore: photoStore)

    let appear = Task { await model.onAppear(category: .people) }
    await waitUntil { model.content != .loading }
    #expect(model.content == .loaded([]))

    await cancelAndWait(appear)
  }

  @Test("처음 읽지 못하면 실패다")
  func firstReadFailureShowsFailed() async {
    let photoStore = PhotoStoreClientFake(images: [.dated(id: "a", nil)], assetsErrors: [0: .failed])
    let model = CategoryModel.fixture(photoStore: photoStore)

    let appear = Task { await model.onAppear(category: .people) }
    await waitUntil { model.content == .failed }

    await cancelAndWait(appear)
  }

  @Test("저장소가 없으면 실패다")
  func missingStoreShowsFailed() async {
    let model = CategoryModel(photoLibrary: PhotoLibraryClientFake(), photoStore: nil, calendar: .seoul)

    await model.onAppear(category: .people)

    #expect(model.category == .people)
    #expect(model.content == .failed)
  }

  @Test("실패 뒤 다시 시도하면 불러오는 중을 거쳐 다시 읽어 격자가 보인다")
  func retryAfterFailureReloads() async {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(
      images: [.dated(id: "a", nil)],
      assetsErrors: [0: .failed],
      onAssets: { await gates.pass($0) }
    )
    let model = CategoryModel.fixture(photoStore: photoStore)
    let appear = Task { await model.onAppear(category: .people) }
    await waitUntil { model.content == .failed }

    model.retryButtonTapped()
    #expect(model.content == .loading)
    await waitUntil { gates.hasEntered(1) }
    #expect(model.content == .loading)

    gates.open(1)
    await waitUntil { model.content.sectionIDs == [["a"]] }

    await cancelAndWait(appear)
  }

  @Test("실패가 아니면 다시 시도는 아무것도 하지 않는다")
  func retryIgnoredUnlessFailed() async {
    let photoStore = PhotoStoreClientFake(images: [.dated(id: "a", nil)])
    let model = CategoryModel.fixture(photoStore: photoStore)
    let appear = Task { await model.onAppear(category: .people) }
    await waitUntil { model.content.sectionIDs == [["a"]] }

    model.retryButtonTapped()
    await settle()

    #expect(model.content.sectionIDs == [["a"]])
    #expect(photoStore.assetsCallCount == 1)

    await cancelAndWait(appear)
  }

  @Test("다시 읽기에 실패하면 지난 섹션을 둔다")
  func reloadFailureKeepsSections() async {
    // 실패한 두 번째 읽기를 처리한 뒤에야 세 번째 읽기가 시작되므로, 세 번째를 붙잡아 실패 처리 뒤의 상태를 본다.
    let gates = CallGates(holding: [2])
    let photoStore = PhotoStoreClientFake(
      images: [.dated(id: "a", nil)],
      assetsErrors: [1: .failed],
      onAssets: { await gates.pass($0) }
    )
    let model = CategoryModel.fixture(photoStore: photoStore)
    let appear = Task { await model.onAppear(category: .people) }
    await waitUntil { model.content.sectionIDs == [["a"]] }

    try? await photoStore.save([.dated(id: "b", nil)])
    model.libraryStoreChanged()
    await waitUntil { photoStore.assetsCallCount == 2 }
    model.libraryStoreChanged()
    await waitUntil { gates.hasEntered(2) }
    #expect(model.content.sectionIDs == [["a"]])

    gates.open(2)
    await waitUntil { model.content.sectionIDs == [["a", "b"]] }

    await cancelAndWait(appear)
  }

  @Test("저장소 변경 신호를 받으면 다시 읽어 새 이미지가 더해지고 지운 이미지가 빠진다")
  func storeChangeAddsAndRemoves() async {
    let photoStore = PhotoStoreClientFake(images: [
      .dated(id: "old", .seoul(2026, 9, 1, hour: 12)),
      .dated(id: "kept", .seoul(2026, 10, 1, hour: 12)),
    ])
    let model = CategoryModel.fixture(photoStore: photoStore)
    let appear = Task { await model.onAppear(category: .people) }
    await waitUntil { model.content.sectionIDs == [["kept"], ["old"]] }

    try? await photoStore.save([.dated(id: "new", .seoul(2026, 10, 5, hour: 12))])
    try? await photoStore.delete(ids: ["old"])
    model.libraryStoreChanged()

    await waitUntil { model.content.sectionIDs == [["new", "kept"]] }

    await cancelAndWait(appear)
  }

  @Test("다시 읽는 중 온 신호 여럿은 끝난 뒤 한 번으로 합친다")
  func changesDuringReloadCoalesce() async {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(images: [.dated(id: "a", nil)], onAssets: { await gates.pass($0) })
    let model = CategoryModel.fixture(photoStore: photoStore)
    let appear = Task { await model.onAppear(category: .people) }
    await waitUntil { model.content.sectionIDs == [["a"]] }

    model.libraryStoreChanged()
    await waitUntil { gates.hasEntered(1) }
    model.libraryStoreChanged()
    model.libraryStoreChanged()
    model.libraryStoreChanged()
    gates.open(1)

    // 처음 읽기, 신호로 한 번, 합친 신호로 한 번.
    await waitUntil { photoStore.assetsCallCount == 3 }
    await settle()
    #expect(photoStore.assetsCallCount == 3)

    await cancelAndWait(appear)
  }

  @Test("다시 읽어도 같으면 내용을 바꾸지 않는다")
  func unchangedReloadKeepsContent() async {
    // 두 번째 읽기를 처리한 뒤에야 세 번째 읽기가 시작되므로, 세 번째를 붙잡아 두 번째 처리가 끝났음을 안다.
    let gates = CallGates(holding: [2])
    let photoStore = PhotoStoreClientFake(images: [.dated(id: "a", nil)], onAssets: { await gates.pass($0) })
    let model = CategoryModel.fixture(photoStore: photoStore)
    let appear = Task { await model.onAppear(category: .people) }
    await waitUntil { model.content.sectionIDs == [["a"]] }
    let changes = CallCounter()
    withObservationTracking {
      _ = model.content
    } onChange: {
      _ = changes.next()
    }

    model.libraryStoreChanged()
    await waitUntil { photoStore.assetsCallCount == 2 }
    model.libraryStoreChanged()
    await waitUntil { gates.hasEntered(2) }

    #expect(changes.next() == 0)

    gates.open(2)
    await cancelAndWait(appear)
  }

  @Test("화면을 닫은 뒤 늦게 끝난 조회는 내용을 바꾸지 않는다")
  func lateReadAfterCloseIsDropped() async {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let photoStore = PhotoStoreClientFake(images: [.dated(id: "a", nil)], onAssets: { await gates.pass($0) })
    let model = CategoryModel.fixture(photoStore: photoStore)
    let appear = Task { await model.onAppear(category: .people) }
    await waitUntil { gates.hasEntered(0) }

    appear.cancel()
    gates.open(0)
    await appear.value

    #expect(model.content == .loading)
  }

  @Test("다른 카테고리를 연 뒤 늦게 끝난 지난 조회는 버린다")
  func lateReadFromPreviousCategoryIsDropped() async {
    let gates = CallGates(holding: [0])
    let photoStore = PhotoStoreClientFake(
      images: [.dated(id: "person", nil), .dated(id: "dish", nil, categories: [.food])],
      onAssets: { await gates.pass($0) }
    )
    let model = CategoryModel.fixture(photoStore: photoStore)
    // 지난 화면의 Task 가 아직 취소되지 않은 채로 다음 화면이 열린 경우다.
    let previous = Task { await model.onAppear(category: .people) }
    await waitUntil { gates.hasEntered(0) }
    let current = Task { await model.onAppear(category: .food) }
    await waitUntil { model.content.sectionIDs == [["dish"]] }

    gates.open(0)
    await settle()

    #expect(model.category == .food)
    #expect(model.content.sectionIDs == [["dish"]])

    await cancelAndWait(previous)
    await cancelAndWait(current)
  }

  @Test("다른 카테고리를 열면 지난 섹션 대신 불러오는 중부터 보인다")
  func switchingCategoryStartsFromLoading() async {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(
      images: [.dated(id: "person", nil), .dated(id: "dish", nil, categories: [.food])],
      onAssets: { await gates.pass($0) }
    )
    let model = CategoryModel.fixture(photoStore: photoStore)
    let first = Task { await model.onAppear(category: .people) }
    await waitUntil { model.content.sectionIDs == [["person"]] }
    await cancelAndWait(first)

    let second = Task { await model.onAppear(category: .food) }
    await waitUntil { gates.hasEntered(1) }
    #expect(model.category == .food)
    #expect(model.content == .loading)

    gates.open(1)
    await waitUntil { model.content.sectionIDs == [["dish"]] }

    await cancelAndWait(second)
  }

  @Test("같은 카테고리를 다시 열면 지난 섹션을 둔 채 다시 읽는다")
  func reopeningSameCategoryKeepsSections() async {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(images: [.dated(id: "a", nil)], onAssets: { await gates.pass($0) })
    let model = CategoryModel.fixture(photoStore: photoStore)
    let first = Task { await model.onAppear(category: .people) }
    await waitUntil { model.content.sectionIDs == [["a"]] }
    await cancelAndWait(first)
    try? await photoStore.save([.dated(id: "b", nil)])

    let second = Task { await model.onAppear(category: .people) }
    await waitUntil { gates.hasEntered(1) }
    #expect(model.content.sectionIDs == [["a"]])

    gates.open(1)
    await waitUntil { model.content.sectionIDs == [["a", "b"]] }

    await cancelAndWait(second)
  }

  @Test("화면이 닫혀 있을 때 온 신호는 버리고, 다시 열면 읽는다")
  func changeWhileClosedIsIgnored() async {
    let photoStore = PhotoStoreClientFake(images: [.dated(id: "a", nil)])
    let model = CategoryModel.fixture(photoStore: photoStore)
    let first = Task { await model.onAppear(category: .people) }
    await waitUntil { model.content.sectionIDs == [["a"]] }
    await cancelAndWait(first)

    try? await photoStore.save([.dated(id: "b", nil)])
    model.libraryStoreChanged()
    await settle()
    #expect(photoStore.assetsCallCount == 1)
    #expect(model.content.sectionIDs == [["a"]])

    let second = Task { await model.onAppear(category: .people) }
    await waitUntil { model.content.sectionIDs == [["a", "b"]] }
    #expect(photoStore.assetsCallCount == 2)

    await cancelAndWait(second)
  }
}

/// 메인 밖 섹션 계산 뒤의 버림 규칙과, 상세에서 돌아올 때의 다시 읽기.
/// 계산 단계에서 멈출 때는 `sectioning` 을 주입해 `CallGates` 로 붙잡는다.
@MainActor
struct CategoryModelSectioningTests {
  @Test("섹션 계산 중에 화면을 닫으면 늦게 끝난 계산 결과로 내용을 바꾸지 않는다")
  func lateSectioningAfterCloseIsDropped() async {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let photoStore = PhotoStoreClientFake(images: [.dated(id: "a", nil)])
    let model = CategoryModel.gatedSectioning(photoStore: photoStore, gates: gates)
    let appear = Task { await model.onAppear(category: .people) }
    await waitUntil { gates.hasEntered(0) }

    appear.cancel()
    gates.open(0)
    await appear.value

    #expect(model.content == .loading)
  }

  @Test("섹션 계산 중에 다른 카테고리를 열면 지난 계산 결과를 버린다")
  func lateSectioningFromPreviousCategoryIsDropped() async {
    let gates = CallGates(holding: [0])
    let photoStore = PhotoStoreClientFake(images: [
      .dated(id: "person", nil),
      .dated(id: "dish", nil, categories: [.food]),
    ])
    let model = CategoryModel.gatedSectioning(photoStore: photoStore, gates: gates)
    // 지난 화면의 Task 가 아직 취소되지 않은 채로 다음 화면이 열린 경우다.
    let previous = Task { await model.onAppear(category: .people) }
    await waitUntil { gates.hasEntered(0) }
    let current = Task { await model.onAppear(category: .food) }
    await waitUntil { model.content.sectionIDs == [["dish"]] }

    gates.open(0)
    await settle()

    #expect(model.category == .food)
    #expect(model.content.sectionIDs == [["dish"]])
    await cancelAndWait(previous)
    await cancelAndWait(current)
  }

  @Test("상세에서 돌아와 같은 카테고리를 다시 열면, 그사이 버린 신호 대신 지난 격자를 둔 채 한 번 다시 읽는다")
  func returnFromDetailReloadsOnce() async {
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(images: [.dated(id: "a", nil)], onAssets: { await gates.pass($0) })
    let model = CategoryModel.fixture(photoStore: photoStore)
    let first = Task { await model.onAppear(category: .people) }
    await waitUntil { model.content.sectionIDs == [["a"]] }

    // 상세가 덮어 카테고리 화면의 Task 가 끝난 동안 저장소가 바뀐다.
    await cancelAndWait(first)
    try? await photoStore.save([.dated(id: "b", nil)])
    model.libraryStoreChanged()
    await settle()
    #expect(photoStore.assetsCallCount == 1)

    let back = Task { await model.onAppear(category: .people) }
    await waitUntil { gates.hasEntered(1) }
    #expect(model.content.sectionIDs == [["a"]])

    gates.open(1)
    await waitUntil { model.content.sectionIDs == [["a", "b"]] }
    await settle()
    #expect(photoStore.assetsCallCount == 2)
    await cancelAndWait(back)
  }
}
