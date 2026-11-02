import Core
import Foundation
import PhotoLibraryInterface
import PhotoLibraryTesting
import Testing
@testable import LibraryFeature

/// 상세에서 돌아올 위치(`CategoryModel.detailReturn`). 상세 수명은 닫힐 때까지 돌아오지 않으므로 Task 로 부르고 끝에 취소한다.
@MainActor
struct CategoryModelDetailReturnTests {
  static let ids = ["p0", "p1", "p2"]

  @Test("연 곳이 있는 상세를 열면 돌아올 위치는 연 곳과 누른 장이다")
  func openingSetsReturn() async {
    let model = Self.model()
    let origin = PhotoDetailOrigin(visit: UUID(), section: 3)

    let detail = Task { await model.detailAppeared(ids: Self.ids, index: 1, origin: origin) }
    await waitUntil { model.detailReturn != nil }
    #expect(model.detailReturn == PhotoDetailReturn(origin: origin, id: "p1"))

    await cancelAndWait(detail)
  }

  @Test("연 곳이 없는 상세(최근 스크린샷 화면·한 장)를 열면 남아 있던 돌아올 위치를 지운다")
  func openingWithoutOriginClearsReturn() async {
    let model = Self.model()
    let opened = Task {
      await model.detailAppeared(ids: Self.ids, index: 0, origin: PhotoDetailOrigin(visit: UUID(), section: 0))
    }
    await waitUntil { model.detailReturn != nil }
    await cancelAndWait(opened)

    let inbox = Task { await model.detailAppeared(id: "p2") }
    await waitUntil { model.detailImages["p2"] != nil }
    #expect(model.detailReturn == nil)

    await cancelAndWait(inbox)
    #expect(model.detailReturn == nil)
  }

  @Test("넘김을 받아들이면 돌아올 위치가 그 장으로 바뀌고 연 곳은 그대로다. 무시되는 넘김은 바꾸지 않는다")
  func pageChangeMovesReturn() async {
    let model = Self.model()
    let origin = PhotoDetailOrigin(visit: UUID(), section: 1)
    let detail = Task { await model.detailAppeared(ids: Self.ids, index: 0, origin: origin) }
    await waitUntil { model.detailReturn != nil }

    model.detailPageChanged(index: 2, id: "p2")
    #expect(model.detailReturn == PhotoDetailReturn(origin: origin, id: "p2"))

    // 범위 밖 위치, 다른 스냅숏의 식별자.
    model.detailPageChanged(index: 3, id: "p3")
    model.detailPageChanged(index: 1, id: "other")
    #expect(model.detailReturn == PhotoDetailReturn(origin: origin, id: "p2"))

    // 닫혀도 남고, 수명 밖의 넘김은 바꾸지 않는다.
    await cancelAndWait(detail)
    #expect(model.detailReturn == PhotoDetailReturn(origin: origin, id: "p2"))
    model.detailPageChanged(index: 1, id: "p1")
    #expect(model.detailReturn == PhotoDetailReturn(origin: origin, id: "p2"))
  }

  @Test("연 곳이 없는 상세에서는 넘겨도 돌아올 위치를 만들지 않는다")
  func pageChangeWithoutOriginKeepsNil() async {
    let model = Self.model()
    let detail = Task { await model.detailAppeared(ids: Self.ids, index: 0, origin: nil) }
    await waitUntil { model.detailImages["p0"] != nil }

    model.detailPageChanged(index: 1, id: "p1")
    #expect(model.detailReturn == nil)

    await cancelAndWait(detail)
  }

  @Test("돌아올 위치를 썼다는 이벤트는 같은 방문일 때만 비운다")
  func applyClearsOnlyMatchingVisit() async {
    let model = Self.model()
    let origin = PhotoDetailOrigin(visit: UUID(), section: 0)
    let detail = Task { await model.detailAppeared(ids: Self.ids, index: 1, origin: origin) }
    await waitUntil { model.detailReturn != nil }
    await cancelAndWait(detail)

    model.detailReturnApplied(visit: UUID())
    #expect(model.detailReturn == PhotoDetailReturn(origin: origin, id: "p1"))

    model.detailReturnApplied(visit: origin.visit)
    #expect(model.detailReturn == nil)
  }

  @Test("닫고 다른 화면에서 새 상세를 열면 지난 돌아올 위치를 새 연 곳·누른 장으로 덮는다")
  func newDetailReplacesReturn() async {
    let model = Self.model()
    let first = PhotoDetailOrigin(visit: UUID(), section: 0)
    let opened = Task { await model.detailAppeared(ids: Self.ids, index: 0, origin: first) }
    await waitUntil { model.detailReturn != nil }
    model.detailPageChanged(index: 2, id: "p2")
    await cancelAndWait(opened)

    let second = PhotoDetailOrigin(visit: UUID(), section: 2)
    let reopened = Task { await model.detailAppeared(ids: ["q0", "q1"], index: 1, origin: second) }
    await waitUntil { model.detailReturn?.origin == second }
    #expect(model.detailReturn == PhotoDetailReturn(origin: second, id: "q1"))

    // 지난 방문의 적용 이벤트는 새 값을 지우지 않는다.
    model.detailReturnApplied(visit: first.visit)
    #expect(model.detailReturn == PhotoDetailReturn(origin: second, id: "q1"))

    await cancelAndWait(reopened)
  }

  // MARK: - Helpers

  static func model() -> CategoryModel {
    let ids = Self.ids + ["q0", "q1"]
    let photoLibrary = PhotoLibraryClientFake(
      loadImageResults: Dictionary(uniqueKeysWithValues: ids.map { ($0, .success(.stub())) })
    )
    return CategoryModel(photoLibrary: photoLibrary, photoStore: nil)
  }
}
