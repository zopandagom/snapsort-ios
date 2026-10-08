import PhotoLibraryInterface
import PhotoLibraryTesting
import Testing
@testable import LibraryFeature

/// `onAppear()` 는 변경 알림이 끝날 때까지 돌아오지 않는다.
/// 변경 테스트는 구독과 처음 불러오기를 기다린 뒤 변경을 보내고, `finishImageChanges()` 로 끝낸 다음 결과를 확인한다.
@MainActor
struct LibraryModelTests {
  @Test("화면 진입 시 이미지 수를 불러온다", arguments: [0, 3])
  func onAppearLoadsCount(count: Int) async {
    let photoLibrary = PhotoLibraryClientFake(
      currentState: .authorized,
      imageIdentifiers: (0 ..< count).map { "image-\($0)" }
    )
    let model = LibraryModel(photoLibrary: photoLibrary)
    photoLibrary.finishImageChanges()

    await model.onAppear()

    #expect(model.imageCount == count)
  }

  @Test(
    "제한 접근일 때만 isLimited 가 참이다",
    arguments: [
      (PhotoAccessState.limited, true),
      (.authorized, false),
      (.notDetermined, false),
      (.denied, false),
    ]
  )
  func isLimitedReflectsAccessState(state: PhotoAccessState, expected: Bool) {
    let model = LibraryModel(photoLibrary: PhotoLibraryClientFake(currentState: state))

    #expect(model.isLimited == expected)
  }

  @Test("온보딩 전에 만들어져도 화면 진입 시 제한 접근 상태를 다시 읽는다")
  func onAppearRereadsLimitedAccess() async {
    let photoLibrary = PhotoLibraryClientFake(currentState: .notDetermined, stateAfterRequest: .limited)
    let model = LibraryModel(photoLibrary: photoLibrary)
    _ = await photoLibrary.requestAccess()
    photoLibrary.finishImageChanges()

    await model.onAppear()

    #expect(model.isLimited)
  }

  @Test("보관함이 바뀌면 이미지 수를 다시 불러온다")
  func imageChangeReloadsCount() async {
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized, imageIdentifiers: ["image-0"])
    let model = LibraryModel(photoLibrary: photoLibrary)
    let appear = Task { await model.onAppear() }
    await waitUntil { photoLibrary.imageChangesSubscriberCount == 1 && model.imageCount == 1 }

    photoLibrary.sendImageChange(imageIdentifiers: ["image-0", "image-1"])
    photoLibrary.finishImageChanges()
    await appear.value

    #expect(model.imageCount == 2)
  }

  @Test("보관함 변경과 함께 제한 접근이 풀리면 배너를 내린다")
  func imageChangeRereadsLimitedAccess() async {
    let photoLibrary = PhotoLibraryClientFake(currentState: .limited, imageIdentifiers: ["image-0"])
    let model = LibraryModel(photoLibrary: photoLibrary)
    let appear = Task { await model.onAppear() }
    await waitUntil { photoLibrary.imageChangesSubscriberCount == 1 && model.imageCount == 1 }

    photoLibrary.sendImageChange(imageIdentifiers: ["image-0", "image-1"], accessState: .authorized)
    photoLibrary.finishImageChanges()
    await appear.value

    #expect(!model.isLimited)
  }

  @Test("화면이 사라져 Task 가 취소되면 변경 구독을 끝낸다")
  func cancellingEndsSubscription() async {
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
    let model = LibraryModel(photoLibrary: photoLibrary)
    let appear = Task { await model.onAppear() }
    await waitUntil { photoLibrary.imageChangesSubscriberCount == 1 }

    appear.cancel()
    await appear.value

    #expect(photoLibrary.imageChangesSubscriberCount == 0)
  }

  @Test("화면에 다시 들어오면 변경을 다시 구독한다")
  func reappearResubscribes() async {
    let photoLibrary = PhotoLibraryClientFake(currentState: .authorized, imageIdentifiers: ["image-0"])
    let model = LibraryModel(photoLibrary: photoLibrary)
    let firstAppear = Task { await model.onAppear() }
    await waitUntil { photoLibrary.imageChangesSubscriberCount == 1 }
    firstAppear.cancel()
    await firstAppear.value

    // 화면 밖에 있는 동안 바뀐 보관함은 다시 진입할 때 처음 불러오기로 읽는다.
    photoLibrary.sendImageChange(imageIdentifiers: ["image-0", "image-1"])
    let secondAppear = Task { await model.onAppear() }
    await waitUntil { photoLibrary.imageChangesSubscriberCount == 1 && model.imageCount == 2 }
    photoLibrary.sendImageChange(imageIdentifiers: ["image-0", "image-1", "image-2"])
    photoLibrary.finishImageChanges()
    await secondAppear.value

    #expect(model.imageCount == 3)
  }

  @Test("사진 더 선택을 누르면 선택 화면을 띄우고, 고른 사진이 바뀐 알림으로 이미지 수를 다시 불러온다")
  func selectMorePhotosReloadsCount() async {
    let photoLibrary = PhotoLibraryClientFake(
      currentState: .limited,
      imageIdentifiers: ["image-0"],
      imageIdentifiersAfterPicker: ["image-0", "image-1", "image-2"]
    )
    let model = LibraryModel(photoLibrary: photoLibrary)
    let appear = Task { await model.onAppear() }
    await waitUntil { photoLibrary.imageChangesSubscriberCount == 1 && model.imageCount == 1 }

    await model.selectMorePhotosTapped()
    photoLibrary.finishImageChanges()
    await appear.value

    #expect(photoLibrary.limitedPickerPresentCount == 1)
    #expect(model.imageCount == 3)
  }
}

/// `onAppear()` 가 구독과 처음 불러오기를 마칠 때까지 다른 Task 에 실행을 넘기며 기다린다.
/// 변경을 그 뒤에 보내야 처음 불러오기가 아니라 구독 경로로 반영됐는지 검증할 수 있다.
/// Fake 의 async 메서드는 전역 실행기에서 돌아 끝나는 시점이 스케줄링에 달렸으므로, 반복 횟수가 아니라 시간으로 제한한다.
@MainActor
private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
  let deadline = ContinuousClock.now + timeout
  while !condition(), ContinuousClock.now < deadline {
    await Task.yield()
  }
  #expect(condition(), "기다리던 상태가 되지 않았다")
}
