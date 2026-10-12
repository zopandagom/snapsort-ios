import Core
import IndexingInterface
import Observation
import PhotoLibraryInterface
import PhotoStoreInterface

/// 이미지 보관함 화면의 상태와 로직.
/// 상태는 모두 private(set) 이고, View 는 이벤트 메서드 호출로만 상태 변경을 요청한다.
/// 권한 분기는 App 과 OnboardingFeature 가 맡으므로, 이 화면은 읽을 수 있는 권한이 있을 때만 뜬다.
@MainActor
@Observable
public final class LibraryModel {
  public private(set) var imageCount = 0
  /// 사용자가 고른 사진만 읽을 수 있는 제한 접근 상태인지. 화면에 안내 배너를 띄우는 데 쓴다.
  public private(set) var isLimited: Bool
  /// 분류 인덱싱 진행률. 인덱싱을 시작하기 전이나 인덱서가 없으면 nil.
  /// 인덱싱이 멈춰도 마지막 값을 남겨 어디까지 분석했는지 보여 준다.
  public private(set) var indexingProgress: IndexingProgress?
  /// 인덱싱이 중간에 멈췄는지 (저장소를 읽거나 쓰지 못함 등). 화면에 다시 시도 안내를 띄운다.
  /// 인덱서는 보관함 변경을 계속 관찰하므로 정상이면 스트림이 끝나지 않는다. 그래서 스트림이 끝나면 멈춘 것으로 본다.
  public private(set) var isIndexingStopped = false
  /// 분석할 이미지가 남아 인덱싱이 돌고 있는지. 첫 진행률을 받기 전(보관함과 저장소 비교 중)에도 참이다.
  /// 다 분석했거나, 멈췄거나, 화면이 사라져 구독을 끝내면 거짓이다.
  public private(set) var isIndexing = false
  /// 카테고리별 개수. 이미지가 없는 카테고리는 빠진다.
  /// `.travel` 은 여행 사진 수가 아니라 여행 판정으로 찾은 여행 수다.
  public private(set) var categoryCounts: [ImageCategory: Int] = [:]

  /// 개수가 아니라 식별자 집합으로 들고 있어, 처음 조회 결과와 겹치는 변경이 와도 두 번 세지 않는다.
  @ObservationIgnored private var imageIDs: Set<ImageAsset.ID> = [] {
    didSet { self.imageCount = self.imageIDs.count }
  }

  /// 멈춘 인덱싱을 다시 시작하라는 신호. `runIndexing()` 이 구독하는 동안만 의미가 있다.
  @ObservationIgnored private var indexingRetries: AsyncStream<Void>.Continuation?
  /// `runIndexing()` 을 시작할 때마다 하나씩 올린다. 화면을 나갔다 바로 들어오면 취소된 지난 Task 가
  /// 늦게 깨어날 수 있으므로, 인덱싱 상태는 지금 번호의 Task 만 바꾼다.
  @ObservationIgnored private var indexingGeneration = 0

  @ObservationIgnored private let photoLibrary: any PhotoLibraryClient
  @ObservationIgnored private let indexing: (any IndexingClient)?
  @ObservationIgnored private let photoStore: (any PhotoStoreClient)?

  /// 권한 상태는 동기로 읽을 수 있으므로 init 에서 읽어 첫 프레임부터 배너가 보이게 한다.
  /// App 은 온보딩 전에 이 Model 을 만들므로, 화면 진입 때도 다시 읽는다.
  /// - Parameters:
  ///   - indexing: 분류 인덱서.
  ///   - photoStore: 인덱서가 저장한 분류 결과를 읽는 저장소.
  ///   저장소를 열지 못하면(디스크 공간 부족 등) App 이 둘 다 nil 을 넘기고, 분류 없이 보관함만 보여 준다.
  public init(
    photoLibrary: any PhotoLibraryClient,
    indexing: (any IndexingClient)?,
    photoStore: (any PhotoStoreClient)?
  ) {
    self.photoLibrary = photoLibrary
    self.indexing = indexing
    self.photoStore = photoStore
    self.isLimited = photoLibrary.accessState() == .limited
  }

  // MARK: - Events

  /// 이미지 수 관찰과 분류 인덱싱을 함께 시작한다.
  /// View 의 `.task` 수명 동안 이어지고, 화면이 사라져 Task 가 취소되면 둘 다 끝난다.
  public func onAppear() async {
    await withDiscardingTaskGroup { group in
      group.addTask { await self.observeImages() }
      group.addTask { await self.runIndexing() }
    }
  }

  /// 고른 사진이 바뀌면 보관함 변경 알림이 오므로 여기서 따로 다시 불러오지 않는다.
  public func selectMorePhotosTapped() async {
    await self.photoLibrary.presentLimitedLibraryPicker()
  }

  /// 멈춘 인덱싱을 다시 시작한다. 인덱서가 저장된 데까지 건너뛰므로 처음부터 분석하지 않는다.
  /// 다시 시작한 인덱싱도 `onAppear()` 의 Task 에서 돌아, 화면이 사라지면 함께 끝난다.
  public func retryIndexingTapped() {
    guard self.isIndexingStopped else { return }
    // 다시 시작하기 전에 또 눌러 신호가 남으면, 다음에 멈췄을 때 누르지 않아도 다시 시작하므로 바로 푼다.
    self.isIndexingStopped = false
    // 다시 시작할 때까지 비는 사이에 "분류된 이미지가 없습니다"가 보이지 않게 바로 켠다.
    self.isIndexing = true
    self.indexingRetries?.yield()
  }

  // MARK: - Private

  /// 보관함 변경 구독을 먼저 시작하고 처음 불러온다. 그래야 처음 불러오는 동안 생긴 변경도 놓치지 않는다.
  /// 이후에는 바뀐 이미지만 반영하고, 무엇이 바뀌었는지 모를 때만 전체를 다시 불러온다.
  private func observeImages() async {
    let changes = await self.photoLibrary.imageChanges()
    await self.reloadImages()
    for await change in changes {
      switch change {
      case let .incremental(inserted, removed):
        self.refreshLimitedAccess()
        self.imageIDs.subtract(removed)
        self.imageIDs.formUnion(inserted.map(\.id))
      case .reloadAll:
        await self.reloadImages()
      }
    }
  }

  /// 지난 결과로 개수를 먼저 보여 준 뒤 인덱싱을 시작한다. 멈추면 다시 시도 신호를 기다린다.
  /// 개수 조회는 이 Task 안에서만 차례로 해서, 늦게 끝난 옛 조회가 새 개수를 덮지 않는다.
  private func runIndexing() async {
    self.indexingGeneration += 1
    let generation = self.indexingGeneration
    // 멈춘 채 화면을 나갔다 들어오면 지난 멈춤이 남아 있다. 개수를 읽는 동안 지난 다시 시도 안내가 보이지 않게 먼저 푼다.
    if self.indexing != nil {
      self.isIndexingStopped = false
      self.isIndexing = true
    }
    await self.refreshCategoryCounts(generation: generation)
    guard self.isCurrent(generation), !Task.isCancelled, let indexing = self.indexing else { return }
    let (retries, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    self.indexingRetries = continuation
    await self.index(with: indexing, generation: generation)
    for await _ in retries {
      await self.index(with: indexing, generation: generation)
    }
  }

  /// 인덱서는 보관함 변경을 스스로 관찰하므로, 진행률만 받아 상태에 반영한다.
  /// 인덱서는 저장·삭제·여행 교체 뒤마다 진행률을 보내므로, 그때마다 개수를 다시 읽는다.
  /// 기다린 뒤에는 늘 지금 번호인지 확인해, 지난 Task 가 새 Task 의 상태를 덮지 않게 한다.
  private func index(with indexing: any IndexingClient, generation: Int) async {
    guard self.isCurrent(generation) else { return }
    self.isIndexingStopped = false
    self.isIndexing = true
    for await progress in indexing.run() {
      guard self.isCurrent(generation) else { return }
      self.indexingProgress = progress
      self.isIndexing = !progress.isFinished
      await self.refreshCategoryCounts(generation: generation)
    }
    guard self.isCurrent(generation) else { return }
    self.isIndexing = false
    // 화면이 사라져 구독을 끝낸 것은 멈춘 것이 아니다.
    guard !Task.isCancelled else { return }
    // 마지막 진행률 뒤에 저장소를 바꾸고(삭제 등) 멈췄을 수 있으므로 한 번 더 읽는다.
    await self.refreshCategoryCounts(generation: generation)
    guard self.isCurrent(generation), !Task.isCancelled else { return }
    self.isIndexingStopped = true
  }

  /// 저장소를 읽지 못하면 지난 개수를 그대로 둔다. 인덱싱도 같은 저장소를 쓰므로 멈춤 안내로 드러난다.
  private func refreshCategoryCounts(generation: Int) async {
    guard let photoStore = self.photoStore else { return }
    do throws(PhotoStoreError) {
      var counts = try await photoStore.categoryCounts()
      let tripCount = try await photoStore.tripCount()
      if tripCount > 0 {
        counts[.travel] = tripCount
      }
      guard self.isCurrent(generation) else { return }
      self.categoryCounts = counts
    } catch {
      return
    }
  }

  private func isCurrent(_ generation: Int) -> Bool {
    generation == self.indexingGeneration
  }

  /// 권한 상태도 다시 읽어, 앱 실행 중 설정에서 바뀐 제한 접근 상태를 배너에 반영한다.
  private func reloadImages() async {
    self.refreshLimitedAccess()
    self.imageIDs = await Set(self.photoLibrary.fetchImageAssets().map(\.id))
  }

  private func refreshLimitedAccess() {
    self.isLimited = self.photoLibrary.accessState() == .limited
  }
}
