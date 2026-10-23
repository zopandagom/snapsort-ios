import Core
import PhotoStoreInterface
import Synchronization

/// 테스트와 Example 앱용 대역. 메모리에 저장해 Impl 처럼 저장·삭제·추출 값 저장·여행 교체가 조회에 반영되고,
/// 저장·삭제·추출 값 저장·보강 결과 저장 요청을 기록한다. 추출 규칙 버전과 보강 버전은 두지 않는다(버전 동작은 Impl 테스트가 본다).
/// 그래서 만료 예정 조회(`upcomingGifticonExpiries`)는 추출 값의 만료일만 보고, 보강 상태는 `IndexedImage.gifticonModelFill`
/// 로만 다룬다(`.stale`·`.sourcesUnknown` 은 테스트가 그 상태의 이미지를 넣어 만든다. 출처를 모르는 옛 행을 `.sourcesUnknown` 으로
/// 읽는 판정은 Impl 만 한다). 사용 여부는 `usedIDs` 로 따로 두고 Impl 처럼 `save`·`delete` 가 기프티콘에서 빠진 행을 지운다.
/// 모든 호출의 실패와 따로, 기프티콘 소급 추출 호출만의 실패(`gifticonError`), 소급 보강 호출만의 실패(`modelFillError`),
/// 특정 식별자를 읽는 `images(ids:)` 만의 실패(`failingOnIDRead`), `assets(in:)` 의 호출 번호별 실패(`assetsErrors`)도 정할 수 있다.
/// 기프티콘 목록 읽기의 호출 번호별 실패(`gifticonsErrors`)와 사용 여부 쓰기만의 실패(`setUsedError`)도 정할 수 있다.
/// 늦게 끝나는 읽기·쓰기는 `onAssets`·`onUpcomingGifticonExpiries`·`onGifticons`·`onGifticon`·`onSetGifticonUsed` 훅으로 흉내 낸다.
/// 여행 폴더용으로 장소 캐시(`places`)를 두고 Impl 처럼 `savePlace` 가 여행 키를 확인하고 `replaceTrips` 가 캐시를 정리한다.
/// `trips()`·`assets(ids:)`·`assets(in:createdIn:)` 의 호출 번호별 실패(`tripsErrors`·`tripAssetsErrors`·`periodAssetsErrors`)와
/// 늦은 결과 훅(`onTrips`·`onTripAssets`·`onPeriodAssets`), 장소 캐시 읽기·쓰기만의 실패(`placeError`)도 정할 수 있다.
/// 영수증 추출 값 소급·목록 읽기의 실패와 훅은 `ReceiptOptions`(PhotoStoreClientFake+Receipt.swift)에 있다.
/// 저장 결과가 호출 사이에 남아야 하므로 상태를 Mutex 로 보호하는 class 다.
public final class PhotoStoreClientFake: PhotoStoreClient {
  private let error: PhotoStoreError?
  private let saveLimit: Int?
  private let gifticonSaveLimit: Int?
  private let gifticonError: PhotoStoreError?
  let modelFillError: PhotoStoreError?
  private let failingOnIDRead: Set<ImageAsset.ID>
  private let assetsErrors: [Int: PhotoStoreError]
  private let onAssets: @Sendable (Int) async -> Void
  private let onSaveGifticons: @Sendable ([ImageAsset.ID: GifticonInfo]) async -> Void
  let onUpcomingGifticonExpiries: @Sendable (Int) async -> Void
  let gifticonsErrors: [Int: PhotoStoreError]
  let onGifticons: @Sendable (Int) async -> Void
  let onGifticon: @Sendable (Int) async -> Void
  let setUsedError: PhotoStoreError?
  let onSetGifticonUsed: @Sendable (Int) async -> Void
  let tripFolderOptions: TripFolderOptions
  let receiptOptions: ReceiptOptions
  let state: Mutex<State>

  struct State {
    var images: [ImageAsset.ID: IndexedImage]
    var trips: [Trip]
    var savedBatches: [[IndexedImage]] = []
    var savedGifticonBatches: [[ImageAsset.ID: GifticonInfo]] = []
    var savedModelFillBatches: [[ImageAsset.ID: GifticonModelFillResult]] = []
    var deletedBatches: [Set<ImageAsset.ID>] = []
    var replaceTripsCount = 0
    var missingOnIDRead: Set<ImageAsset.ID> = []
    var upcomingGifticonExpiriesCount = 0
    var assetsCallCount = 0
    var usedIDs: Set<ImageAsset.ID> = []
    var gifticonsCallCount = 0
    var gifticonCallCount = 0
    var setGifticonUsedCount = 0
    var tripFolder = TripFolderState()
    var receipt = ReceiptState()
  }

  /// - Parameters:
  ///   - error: 정하면 모든 호출이 이 실패를 던지고 아무것도 바꾸지 않는다.
  ///   - saveLimit: 정하면 `save` 가 이 횟수만큼 성공한 뒤부터 `.failed` 를 던진다. 작업 도중의 저장 실패를 흉내 낸다.
  ///   - gifticonSaveLimit: 정하면 `saveGifticons` 가 이 횟수만큼 성공한 뒤부터 `.failed` 를 던진다. 기프티콘 소급 추출 도중의 저장 실패를 흉내 낸다.
  ///   - gifticonError: 정하면 `gifticonExtractionPendingIDs`·`saveGifticons` 만 이 실패를 던지고 추출 값을 바꾸지 않는다.
  ///     다른 호출은 성공한다. 기프티콘 소급 추출 대상 조회·저장만의 실패를 흉내 낸다(`error` 는 그 앞의 다른 호출에서 먼저 멈춘다).
  ///   - modelFillError: 정하면 `gifticonModelFillPendingIDs`·`saveGifticonModelFills` 만 이 실패를 던지고 보강 결과를 바꾸지 않는다.
  ///     다른 호출은 성공한다. 소급 보강 대상 조회·저장만의 실패를 흉내 낸다.
  ///   - missingOnIDRead: `images(ids:)` 가 빼고 돌려줄 식별자. 다른 조회에는 있는데 읽을 때 행이 없는 어긋남을 흉내 낸다.
  ///     `restoreIDReads()` 로 푼다.
  ///   - failingOnIDRead: `images(ids:)` 가 이 식별자를 하나라도 요청받으면 `.failed` 를 던진다. 다른 호출과 겹치지 않는 읽기는
  ///     성공한다. 소급 배치처럼 그 식별자를 읽는 호출만 실패하는 경우를 흉내 낸다(2단계 배치와는 대상 식별자가 겹치지 않아 구분된다).
  ///   - onSaveGifticons: `saveGifticons` 가 오류·한도 확인과 쓰기 전에 기다려 부른다. 기프티콘 소급 추출 배치 도중(저장 직전)에
  ///     보관함이 바뀌는 일을 흉내 낸다. 소급은 이미지 로드·OCR 을 하지 않아 그쪽 대역의 훅이 걸리지 않는다.
  ///   - assetsErrors: `assets(in:)` 의 호출 번호(0부터)별 실패. 그 번째 호출만 이 실패를 던지고 다른 호출은 성공한다.
  ///     `error`(모든 호출)가 정해져 있으면 그것이 먼저다. 화면 재조회 도중의 실패와 회복을 흉내 낸다.
  ///   - onAssets: `assets(in:)` 가 오류를 확인하고 결과를 계산한 뒤, 돌려주기 전에 기다려 부른다. 인자는 호출 번호(0부터)다.
  ///     기다리는 동안 저장소가 바뀌어도 앞서 계산한 값을 돌려줘, 늦게 끝난 읽기를 흉내 낸다. 실패하는 호출에서는 부르지 않는다.
  ///   - onUpcomingGifticonExpiries: `upcomingGifticonExpiries(from:)` 가 오류를 확인하고 결과를 계산한 뒤, 돌려주기 전에 기다려 부른다.
  ///     인자는 몇 번째 호출인지(0부터)다. 기다리는 동안 저장소가 바뀌어도 앞서 계산한 값을 돌려줘, 늦게 깨어난 읽기를 흉내 낸다.
  ///   - usedIDs: 처음 사용함인 이미지. 들어간 이미지 중 기프티콘 카테고리인 것만 남긴다.
  ///   - gifticonsErrors: `gifticons()` 의 호출 번호(0부터)별 실패. `assetsErrors` 와 같은 방식이다.
  ///   - onGifticons: `gifticons()` 가 오류를 확인하고 결과를 계산한 뒤, 돌려주기 전에 기다려 부른다. 인자는 호출 번호(0부터)다.
  ///     기다리는 동안 저장소가 바뀌어도 앞서 계산한 값을 돌려준다. 실패하는 호출에서는 부르지 않는다.
  ///   - onGifticon: `gifticon(id:)` 가 결과를 계산한 뒤 돌려주기 전에 기다려 부른다. 인자는 호출 번호(0부터)다.
  ///   - setUsedError: 정하면 `setGifticonUsed` 만 이 실패를 던지고 사용 여부를 바꾸지 않는다. 다른 호출은 성공한다.
  ///   - onSetGifticonUsed: `setGifticonUsed` 가 오류를 확인하고 쓰기 전에 기다려 부른다. 인자는 호출 번호(0부터)다.
  ///     쓰는 동안 화면을 닫거나 다시 누르는 일을 흉내 낸다.
  ///   - places: 처음 장소 캐시. 이름은 `placesLocaleIdentifier` 로 캐시한 것으로 본다. 이름이 nil 이면 시간대만 캐시한 것이다.
  ///     여행 키 확인 없이 그대로 둔다.
  ///   - placesLocaleIdentifier: `places` 의 이름이 캐시된 locale.
  ///   - tripsErrors: `trips()` 의 호출 번호(0부터)별 실패. `assetsErrors` 와 같은 방식이다.
  ///   - onTrips: `trips()` 가 오류를 확인하고 결과를 계산한 뒤, 돌려주기 전에 기다려 부른다. 인자는 호출 번호(0부터)다.
  ///     기다리는 동안 저장소가 바뀌어도 앞서 계산한 값을 돌려준다. 실패하는 호출에서는 부르지 않는다.
  ///   - tripAssetsErrors: `assets(ids:)` 의 호출 번호(0부터)별 실패.
  ///   - onTripAssets: `assets(ids:)` 가 결과를 계산한 뒤 돌려주기 전에 기다려 부른다. `onTrips` 와 같은 방식이다.
  ///   - periodAssetsErrors: `assets(in:createdIn:)` 의 호출 번호(0부터)별 실패.
  ///   - onPeriodAssets: `assets(in:createdIn:)` 가 결과를 계산한 뒤 돌려주기 전에 기다려 부른다. `onTrips` 와 같은 방식이다.
  ///   - placeError: 정하면 `places(for:localeIdentifier:)`·`savePlace` 만 이 실패를 던지고 캐시를 바꾸지 않는다. 다른 호출은 성공한다.
  ///   - receiptError·receiptSaveLimit·onSaveReceipts·receiptsErrors·onReceipts: 영수증용 실패·훅. `ReceiptOptions` 문서 참고.
  public init(
    images: [IndexedImage] = [],
    trips: [Trip] = [],
    error: PhotoStoreError? = nil,
    saveLimit: Int? = nil,
    gifticonSaveLimit: Int? = nil,
    gifticonError: PhotoStoreError? = nil,
    modelFillError: PhotoStoreError? = nil,
    missingOnIDRead: Set<ImageAsset.ID> = [],
    failingOnIDRead: Set<ImageAsset.ID> = [],
    onSaveGifticons: @escaping @Sendable ([ImageAsset.ID: GifticonInfo]) async -> Void = { _ in },
    assetsErrors: [Int: PhotoStoreError] = [:],
    onAssets: @escaping @Sendable (Int) async -> Void = { _ in },
    onUpcomingGifticonExpiries: @escaping @Sendable (Int) async -> Void = { _ in },
    usedIDs: Set<ImageAsset.ID> = [],
    gifticonsErrors: [Int: PhotoStoreError] = [:],
    onGifticons: @escaping @Sendable (Int) async -> Void = { _ in },
    onGifticon: @escaping @Sendable (Int) async -> Void = { _ in },
    setUsedError: PhotoStoreError? = nil,
    onSetGifticonUsed: @escaping @Sendable (Int) async -> Void = { _ in },
    places: [RoundedCoordinate: CachedPlace] = [:],
    placesLocaleIdentifier: String = "ko_KR",
    tripsErrors: [Int: PhotoStoreError] = [:],
    onTrips: @escaping @Sendable (Int) async -> Void = { _ in },
    tripAssetsErrors: [Int: PhotoStoreError] = [:],
    onTripAssets: @escaping @Sendable (Int) async -> Void = { _ in },
    periodAssetsErrors: [Int: PhotoStoreError] = [:],
    onPeriodAssets: @escaping @Sendable (Int) async -> Void = { _ in },
    placeError: PhotoStoreError? = nil,
    receiptError: PhotoStoreError? = nil,
    receiptSaveLimit: Int? = nil,
    onSaveReceipts: @escaping @Sendable ([ImageAsset.ID: ReceiptInfo]) async -> Void = { _ in },
    receiptsErrors: [Int: PhotoStoreError] = [:],
    onReceipts: @escaping @Sendable (Int) async -> Void = { _ in }
  ) {
    self.error = error
    self.saveLimit = saveLimit
    self.gifticonSaveLimit = gifticonSaveLimit
    self.gifticonError = gifticonError
    self.modelFillError = modelFillError
    self.failingOnIDRead = failingOnIDRead
    self.onSaveGifticons = onSaveGifticons
    self.assetsErrors = assetsErrors
    self.onAssets = onAssets
    self.onUpcomingGifticonExpiries = onUpcomingGifticonExpiries
    self.gifticonsErrors = gifticonsErrors
    self.onGifticons = onGifticons
    self.onGifticon = onGifticon
    self.setUsedError = setUsedError
    self.onSetGifticonUsed = onSetGifticonUsed
    self.tripFolderOptions = TripFolderOptions(
      tripsErrors: tripsErrors,
      onTrips: onTrips,
      tripAssetsErrors: tripAssetsErrors,
      onTripAssets: onTripAssets,
      periodAssetsErrors: periodAssetsErrors,
      onPeriodAssets: onPeriodAssets,
      placeError: placeError
    )
    self.receiptOptions = ReceiptOptions(
      error: receiptError,
      saveLimit: receiptSaveLimit,
      onSave: onSaveReceipts,
      receiptsErrors: receiptsErrors,
      onReceipts: onReceipts
    )
    let byID = Dictionary(images.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    self.state = Mutex(State(
      images: byID,
      trips: trips,
      missingOnIDRead: missingOnIDRead,
      usedIDs: usedIDs.filter { byID[$0]?.categories.contains(.gifticon) ?? false },
      tripFolder: TripFolderState(places: Self.storedPlaces(places, localeIdentifier: placesLocaleIdentifier))
    ))
  }

  /// `missingOnIDRead` 를 비워 `images(ids:)` 가 다시 모두 돌려주게 한다.
  public func restoreIDReads() {
    self.state.withLock { $0.missingOnIDRead = [] }
  }

  /// 지금 저장된 이미지. 식별자 순이다.
  public var images: [IndexedImage] {
    self.state.withLock { $0.images.values.sorted { $0.id < $1.id } }
  }

  /// `save` 에 넘긴 이미지 목록을 부른 순서대로.
  public var savedBatches: [[IndexedImage]] {
    self.state.withLock { $0.savedBatches }
  }

  /// `saveGifticons` 에 넘긴 추출 값을 부른 순서대로. 실패한 호출은 빠진다.
  public var savedGifticonBatches: [[ImageAsset.ID: GifticonInfo]] {
    self.state.withLock { $0.savedGifticonBatches }
  }

  /// `saveGifticonModelFills` 에 넘긴 보강 결과를 부른 순서대로. 실패한 호출은 빠진다.
  public var savedModelFillBatches: [[ImageAsset.ID: GifticonModelFillResult]] {
    self.state.withLock { $0.savedModelFillBatches }
  }

  /// `replaceTrips` 가 성공한 횟수.
  public var replaceTripsCount: Int {
    self.state.withLock { $0.replaceTripsCount }
  }

  /// `delete` 에 넘긴 식별자를 부른 순서대로.
  public var deletedBatches: [Set<ImageAsset.ID>] {
    self.state.withLock { $0.deletedBatches }
  }

  /// 지금까지 `assets(in:)` 을 부른 횟수. `assetsErrors` 로 실패한 호출은 포함하고, `error`(모든 호출 실패)로 던진 호출은 세지 않는다
  /// (`throwIfNeeded` 가 번호를 매기기 전에 던진다). 재조회 합치기 테스트가 센다.
  public var assetsCallCount: Int {
    self.state.withLock { $0.assetsCallCount }
  }
}

// 저장·삭제·조회와 기프티콘 소급 추출. 저장 속성은 위 본문에 둔다.
public extension PhotoStoreClientFake {
  func save(_ images: [IndexedImage]) async throws(PhotoStoreError) {
    try self.throwIfNeeded()
    let saved = self.state.withLock { state in
      if let limit = self.saveLimit, state.savedBatches.count >= limit {
        return false
      }
      state.savedBatches.append(images)
      for image in images {
        state.images[image.id] = image
        // Impl 처럼 사용 여부는 저장된 값을 두고, 기프티콘에서 빠지면 지운다.
        if !image.categories.contains(.gifticon) {
          state.usedIDs.remove(image.id)
        }
      }
      return true
    }
    if !saved {
      throw .failed
    }
  }

  func delete(ids: Set<ImageAsset.ID>) async throws(PhotoStoreError) {
    try self.throwIfNeeded()
    self.state.withLock { state in
      state.deletedBatches.append(ids)
      for id in ids {
        state.images[id] = nil
        state.usedIDs.remove(id)
      }
    }
  }

  func indexedIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID> {
    try self.throwIfNeeded()
    return self.state.withLock { Set($0.images.keys) }
  }

  func pendingTextRecognitionIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID> {
    try self.throwIfNeeded()
    return self.state.withLock { Set($0.images.values.filter { $0.textRecognition == .pending }.map(\.id)) }
  }

  func gifticonExtractionPendingIDs() async throws(PhotoStoreError) -> Set<ImageAsset.ID> {
    try self.throwIfNeeded()
    try self.throwGifticonErrorIfNeeded()
    return self.state.withLock { Set($0.images.values.filter(Self.isGifticonExtractionPending).map(\.id)) }
  }

  func saveGifticons(_ gifticons: [ImageAsset.ID: GifticonInfo]) async throws(PhotoStoreError) {
    await self.onSaveGifticons(gifticons)
    try self.throwIfNeeded()
    try self.throwGifticonErrorIfNeeded()
    let saved = self.state.withLock { state in
      if let limit = self.gifticonSaveLimit, state.savedGifticonBatches.count >= limit {
        return false
      }
      state.savedGifticonBatches.append(gifticons)
      for (id, gifticon) in gifticons {
        // Impl 처럼 추출 대기 행만 바꾼다(이미 추출한 행은 덮지 않는다).
        guard let image = state.images[id], Self.isGifticonExtractionPending(image) else {
          continue
        }
        state.images[id] = IndexedImage(
          asset: image.asset,
          labels: image.labels,
          textRecognition: image.textRecognition,
          categories: image.categories,
          gifticon: gifticon,
          // Impl 처럼 규칙으로 다시 추출하면 보강도 다시 한다.
          gifticonModelFill: .initial(for: gifticon),
          receipt: image.receipt
        )
      }
      return true
    }
    if !saved {
      throw .failed
    }
  }

  func images(ids: Set<ImageAsset.ID>) async throws(PhotoStoreError) -> [IndexedImage] {
    try self.throwIfNeeded()
    if !ids.isDisjoint(with: self.failingOnIDRead) {
      throw .failed
    }
    let missing = self.state.withLock { $0.missingOnIDRead }
    return self.images.filter { ids.contains($0.id) && !missing.contains($0.id) }
  }

  /// 프로토콜 약속대로 최신순(생성일 없는 이미지는 맨 뒤, 같으면 식별자 순)으로 돌려준다.
  func images(in category: ImageCategory) async throws(PhotoStoreError) -> [IndexedImage] {
    try self.throwIfNeeded()
    return self.images(inCategory: category)
  }

  /// `images(in:)` 와 같은 이미지의 메타데이터를 같은 순서로 돌려준다.
  func assets(in category: ImageCategory) async throws(PhotoStoreError) -> [ImageAsset] {
    try self.throwIfNeeded()
    let index = self.state.withLock { state in
      defer { state.assetsCallCount += 1 }
      return state.assetsCallCount
    }
    if let error = self.assetsErrors[index] {
      throw error
    }
    let assets = self.images(inCategory: category).map(\.asset)
    await self.onAssets(index)
    return assets
  }

  func categoryCounts() async throws(PhotoStoreError) -> [ImageCategory: Int] {
    try self.throwIfNeeded()
    return self.images.flatMap(\.categories).filter { $0 != .travel }.reduce(into: [:]) { $0[$1, default: 0] += 1 }
  }

  /// 그 카테고리 이미지를 최신순(생성일 없는 이미지는 맨 뒤, 같으면 식별자 순)으로.
  private func images(inCategory category: ImageCategory) -> [IndexedImage] {
    self.images
      // Impl 처럼 `.travel` 은 이미지 카테고리로 다루지 않는다.
      .filter { category != .travel && $0.categories.contains(category) }
      .sorted(by: Self.isNewer)
  }

  /// 최신순. 생성일이 없으면 맨 뒤, 같으면 식별자 순으로 고정한다.
  internal static func isNewer(_ lhs: IndexedImage, than rhs: IndexedImage) -> Bool {
    switch (lhs.asset.creationDate, rhs.asset.creationDate) {
    case let (left?, right?) where left != right:
      left > right
    case (.some, nil):
      true
    case (nil, .some):
      false
    default:
      lhs.id < rhs.id
    }
  }

  /// 기프티콘으로 분류돼 글자를 읽었는데 추출 값이 없다.
  private static func isGifticonExtractionPending(_ image: IndexedImage) -> Bool {
    image.categories.contains(.gifticon) && image.textLines != nil && image.gifticon == nil
  }

  internal func throwIfNeeded() throws(PhotoStoreError) {
    if let error = self.error {
      throw error
    }
  }

  private func throwGifticonErrorIfNeeded() throws(PhotoStoreError) {
    if let error = self.gifticonError {
      throw error
    }
  }
}
