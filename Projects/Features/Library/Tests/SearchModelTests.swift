import Core
import Foundation
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 검색 Model 의 읽기·결과 구성. 검색어와 줄은 지어낸 값이다.
@MainActor
struct SearchModelTests {
  @Test("열면 한 번 읽고, 검색어를 넣으면 맞은 사진을 최신순으로 보인다. OCR 대기 수도 안다")
  func onAppearReadsThenQueryFindsImages() async {
    let older = IndexedImage.searchable(id: "older", ["스타벅스 라떼"], at: .seoul(2026, 9, 1, hour: 9))
    let photoStore = PhotoStoreClientFake(images: [
      older, SearchFixture.starbucks, SearchFixture.coupangCapture, .unreadText(id: "waiting"),
    ])
    let (model, _) = SearchFixture.model(photoStore: photoStore)
    #expect(model.loadState == .loading)

    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }
    #expect(model.pendingTextCount == 1)
    #expect(model.results == nil)
    #expect(photoStore.searchEntriesCallCount == 1)

    model.queryChanged("스타벅스")
    await waitUntil { model.resultImageIDs != nil }
    #expect(model.resultImageIDs == ["starbucks", "older"])
    #expect(model.results?.query == "스타벅스")
    #expect(model.hasQuery)

    await cancelAndWait(appear)
  }

  @Test("묶음 값 이름으로도 찾고, 맞은 곳은 이름으로 보인다")
  func captureGroupNameMatches() async {
    let photoStore = PhotoStoreClientFake(images: [SearchFixture.starbucks, SearchFixture.coupangCapture])
    let (model, _) = SearchFixture.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }

    model.queryChanged("쿠팡")
    await waitUntil { model.resultImageIDs != nil }
    #expect(model.resultImageIDs == ["coupang"])
    #expect(model.results?.images.first?.match == .group("쿠팡"))

    await cancelAndWait(appear)
  }

  @Test("카테고리 줄, 여행 줄, 사진 줄이 함께 맞을 수 있다")
  func categoriesTripsAndImagesTogether() async {
    let chat = IndexedImage.searchable(id: "chat", ["대화 내용"], at: .seoul(2026, 10, 1, hour: 9), categories: [.chat])
    let photoStore = PhotoStoreClientFake(
      images: [chat] + TripFixture.photos(of: TripFixture.jeju),
      trips: [TripFixture.jeju],
      places: [TripFixture.jejuKey: CachedPlace(name: .named("대화 마을"), timeZoneIdentifier: "Asia/Seoul")]
    )
    let (model, _) = SearchFixture.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }

    model.queryChanged("대화")
    await waitUntil { model.results != nil }
    #expect(model.results?.categories.map(\.category) == [.chat])
    #expect(model.results?.categories.first?.count == 1)
    #expect(model.results?.trips.map(\.placeName) == ["대화 마을"])
    #expect(model.results?.trips.map(\.id) == ["jeju-0"])
    #expect(model.resultImageIDs == ["chat"])

    await cancelAndWait(appear)
  }

  @Test("이미지가 없는 카테고리와 열 수 있는 여행이 없는 여행 카테고리는 카테고리 줄에서 빠진다")
  func emptyCategoriesAreOmitted() async {
    // 지도 이미지는 없다. 여행은 사진 식별자가 없어 열 수 없다.
    let emptyTrip = Trip(
      assetIDs: [],
      startDate: .seoul(2026, 7, 1, hour: 9),
      endDate: .seoul(2026, 7, 2, hour: 9),
      center: TripFixture.jejuCenter
    )
    let photoStore = PhotoStoreClientFake(images: [SearchFixture.starbucks], trips: [emptyTrip])
    let (model, _) = SearchFixture.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }

    model.queryChanged("지도")
    await waitUntil { model.results != nil }
    #expect(model.results?.isEmpty == true)
    model.queryChanged("여행")
    await waitUntil { model.results?.query == "여행" }
    #expect(model.results?.isEmpty == true)

    await cancelAndWait(appear)
  }

  @Test("여행이 있으면 여행 카테고리 줄이 여행 수와 함께 보인다")
  func travelCategoryShowsWithTripCount() async {
    let photoStore = PhotoStoreClientFake(
      images: TripFixture.photos(of: TripFixture.jeju) + TripFixture.photos(of: TripFixture.tokyo),
      trips: [TripFixture.jeju, TripFixture.tokyo]
    )
    let (model, _) = SearchFixture.model(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { model.loadState == .loaded }

    model.queryChanged("여행")
    await waitUntil { model.results != nil }
    #expect(model.results?.categories == [SearchCategoryHit(category: .travel, count: 2)])

    await cancelAndWait(appear)
  }

  // MARK: - 저장소 없음

  @Test("저장소가 없으면 검색할 수 없다")
  func noStoreIsUnavailable() async {
    let (model, _) = SearchFixture.model(photoStore: nil)
    await model.onAppear()
    #expect(model.loadState == .unavailable)
    model.retryButtonTapped()
    #expect(model.loadState == .unavailable)
  }
}
