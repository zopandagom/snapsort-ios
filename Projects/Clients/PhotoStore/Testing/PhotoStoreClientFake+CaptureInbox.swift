import Core
import Foundation
import PhotoStoreInterface
import Synchronization

// 캡처 인박스 (docs/ARCHITECTURE.md §4 정리 도우미).
public extension PhotoStoreClientFake {
  /// `captureInboxScreenshots(createdSince:)` 를 부른 횟수. `captureInboxErrors` 로 실패한 호출은 포함하고, `error` 로 던진 호출은 세지 않는다.
  var captureInboxCallCount: Int {
    self.state.withLock { $0.captureInbox.callCount }
  }

  /// 호출마다 받은 `createdSince`, 순서대로. 실패한 호출도 포함한다(`error` 로 던진 호출은 뺀다).
  var captureInboxSinceArguments: [Date] {
    self.state.withLock { $0.captureInbox.sinceArguments }
  }

  /// 캡처 인박스에서 보관한 이미지. 행이 지워지면(`delete`) 함께 빠진다.
  var keptInCaptureInboxIDs: Set<ImageAsset.ID> {
    self.state.withLock { $0.captureInbox.keptIDs }
  }

  /// `keepInCaptureInbox(id:)` 가 결과(true·false)를 돌려준 횟수. 실패한 호출은 세지 않는다.
  var keepInCaptureInboxCount: Int {
    self.state.withLock { $0.captureInbox.keepCount }
  }

  /// Impl 과 같은 표: 스크린샷이고 생성일이 `createdSince` 이상이며 보관하지 않은 이미지를 최신순(같으면 식별자 순)으로. 생성일 없으면 뺀다.
  func captureInboxScreenshots(createdSince: Date) async throws(PhotoStoreError) -> [ImageAsset] {
    try self.throwIfNeeded()
    let (index, assets) = self.state.withLock { state in
      defer { state.captureInbox.callCount += 1 }
      state.captureInbox.sinceArguments.append(createdSince)
      let assets = state.images.values
        .filter { image in
          guard image.asset.isScreenshot, !state.captureInbox.keptIDs.contains(image.id),
                let created = image.asset.creationDate
          else { return false }
          return created >= createdSince
        }
        .sorted(by: Self.isNewer)
        .map(\.asset)
      return (state.captureInbox.callCount, assets)
    }
    if let error = self.captureInboxOptions.errors[index] {
      throw error
    }
    await self.captureInboxOptions.onScreenshots(index)
    return assets
  }

  /// 행이 있으면 보관하고 true, 없으면 false. `keepError` 가 있으면 아무것도 바꾸지 않고 던진다.
  /// 오류를 확인하기 전에 `onKeep` 을 기다려 부른다.
  func keepInCaptureInbox(id: ImageAsset.ID) async throws(PhotoStoreError) -> Bool {
    let index = self.state.withLock { state in
      defer { state.captureInbox.keepCallCount += 1 }
      return state.captureInbox.keepCallCount
    }
    await self.captureInboxOptions.onKeep(index)
    try self.throwIfNeeded()
    if let error = self.captureInboxOptions.keepError {
      throw error
    }
    return self.state.withLock { state in
      state.captureInbox.keepCount += 1
      guard state.images[id] != nil else { return false }
      state.captureInbox.keptIDs.insert(id)
      return true
    }
  }
}

extension PhotoStoreClientFake {
  /// 캡처 인박스 읽기·쓰기용 실패·훅.
  struct CaptureInboxOptions {
    /// `captureInboxScreenshots` 의 호출 번호(0부터)별 실패. 그 번째 호출만 이 실패를 던지고 다른 호출은 성공한다.
    /// `error`(모든 호출)가 정해져 있으면 그것이 먼저다.
    let errors: [Int: PhotoStoreError]
    /// `captureInboxScreenshots` 가 오류를 확인하고 결과를 계산한 뒤, 돌려주기 전에 기다려 부른다. 인자는 호출 번호(0부터)다.
    /// 기다리는 동안 저장소가 바뀌어도 앞서 계산한 값을 돌려줘, 늦게 끝난 읽기를 흉내 낸다. 실패하는 호출에서는 부르지 않는다.
    let onScreenshots: @Sendable (Int) async -> Void
    /// 정하면 `keepInCaptureInbox` 만 이 실패를 던지고 아무것도 바꾸지 않는다. 다른 호출은 성공한다.
    let keepError: PhotoStoreError?
    /// `keepInCaptureInbox` 가 오류를 확인하고 쓰기 전에 기다려 부른다. 인자는 호출 번호(0부터, 실패하는 호출도 센다)다.
    /// 늦게 끝나는 보관 쓰기를 흉내 낸다.
    let onKeep: @Sendable (Int) async -> Void
  }

  /// 캡처 인박스용 기록.
  struct CaptureInboxState {
    var keptIDs: Set<ImageAsset.ID> = []
    var callCount = 0
    var keepCount = 0
    /// `onKeep` 에 넘길 다음 호출 번호.
    var keepCallCount = 0
    var sinceArguments: [Date] = []
  }
}

extension PhotoStoreClientFake {
  /// `init` 이 쓰는 처음 상태(장소 캐시는 `init` 이 따로 채운다). 사용 여부는 기프티콘에만, 캡처 인박스 보관은 들어간 이미지에만 남긴다.
  static func seed(
    _ images: [IndexedImage],
    _ trips: [Trip],
    _ missingOnIDRead: Set<ImageAsset.ID>,
    _ usedIDs: Set<ImageAsset.ID>,
    _ keptInCaptureInbox: Set<ImageAsset.ID>
  ) -> Mutex<State> {
    let byID = Dictionary(images.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    return Mutex(State(
      images: byID,
      trips: trips,
      missingOnIDRead: missingOnIDRead,
      usedIDs: usedIDs.filter { byID[$0]?.categories.contains(.gifticon) ?? false },
      captureInbox: CaptureInboxState(keptIDs: keptInCaptureInbox.filter { byID[$0] != nil })
    ))
  }
}
