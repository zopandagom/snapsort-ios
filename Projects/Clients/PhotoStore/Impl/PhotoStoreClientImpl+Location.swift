import Foundation
import PhotoStoreInterface
import SwiftData

/// 저장 파일 위치: 앱과 위젯이 함께 여는 App Group 컨테이너의 `PhotoStore/PhotoStore.store`
/// (docs/ARCHITECTURE.md §4 저장소). 두 조립 지점(App·위젯 Extension)이 같은 계산을 쓴다.
public extension PhotoStoreClientImpl {
  /// 이 번들의 App Group 컨테이너. Info.plist 에 group 이름이 없거나 entitlement 가 없는 빌드(서명 없는 시뮬레이터 빌드)면 nil.
  static func appGroupContainer(bundle: Bundle = .main) -> URL? {
    guard let identifier = bundle.object(forInfoDictionaryKey: appGroupInfoKey) as? String else { return nil }
    return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
  }

  /// App 이 저장소를 열기 전에 동기로 부른다. 옛 위치(`legacyParent/PhotoStore/`)에만 저장 파일이 있으면 폴더째(-wal·-shm 함께)
  /// group 컨테이너로 옮기고, 쓸 저장 파일 위치를 돌려준다. 컨테이너가 nil 이거나 옮기지 못하면 옛 위치를 돌려주고
  /// 옛 폴더를 그대로 둔다(다음 실행에 처음부터 다시).
  ///
  /// group 폴더는 같은 컨테이너 안 임시 폴더에 완성한 복사본을 rename 해서만 만들고, 옛 폴더는 그 rename 뒤에만 지운다.
  /// 그래서 group 폴더에 저장 파일이 있으면 늘 완전한 저장소다. 양쪽에 다 있으면 group 쪽을 쓰고 옛 폴더는 지우지 않는다
  /// (어느 쪽에 사용자가 남긴 표시가 있는지 모른다).
  /// 경로에 컨테이너 UUID 가 들어가므로 로그를 남기지 않는다.
  static func preparedStoreURL(
    groupContainer: URL?,
    legacyParent: URL,
    fileManager: FileManager = .default
  ) -> URL {
    let legacyFolder = legacyParent.appending(path: Self.folderName, directoryHint: .isDirectory)
    let legacyStore = Self.storeURL(in: legacyFolder)
    guard let groupContainer else { return legacyStore }
    let groupFolder = groupContainer.appending(path: Self.folderName, directoryHint: .isDirectory)
    let groupStore = Self.storeURL(in: groupFolder)
    let movingFolder = groupContainer.appending(path: Self.movingFolderName, directoryHint: .isDirectory)

    guard !Self.exists(groupStore, fileManager), Self.exists(legacyStore, fileManager) else {
      // group 에 있거나 새 설치. 지난 실행이 복사 중 끝나 남긴 임시 폴더만 치운다.
      try? fileManager.removeItem(at: movingFolder)
      return groupStore
    }
    // 남은 임시 폴더(복사 중 끝남)와 저장 파일 없는 group 폴더는 잃을 것이 없다. 옛 폴더가 그대로라 처음부터 다시 옮긴다.
    do {
      for folder in [movingFolder, groupFolder] where Self.exists(folder, fileManager) {
        try fileManager.removeItem(at: folder)
      }
    } catch {
      return legacyStore
    }
    do {
      // 같은 볼륨(APFS)이면 복제라 바로 끝난다. 다른 볼륨이면 실제 복사라 끝까지 마친 사본만 rename 한다.
      try fileManager.copyItem(at: legacyFolder, to: movingFolder)
      // 같은 디렉터리 안 rename 이라 원자적이다. 있는 폴더 위로는 실패하므로 위에서 group 폴더를 지웠다.
      try fileManager.moveItem(at: movingFolder, to: groupFolder)
    } catch {
      try? fileManager.removeItem(at: movingFolder)
      return legacyStore
    }
    // 실패하면 쓰지 않는 사본으로 남는다. 다음 실행은 group 쪽을 쓴다.
    try? fileManager.removeItem(at: legacyFolder)
    return groupStore
  }

  /// 위젯이 읽을 저장 파일. 컨테이너가 nil 이거나 앱이 아직 만들지 않았으면 nil.
  /// 없는 파일을 읽기 전용으로 열면 실패하며 오류 로그를 남기므로 미리 거른다.
  static func sharedStoreURL(groupContainer: URL?) -> URL? {
    guard let groupContainer else { return nil }
    let url = Self.storeURL(in: groupContainer.appending(path: Self.folderName, directoryHint: .isDirectory))
    return Self.exists(url, .default) ? url : nil
  }

  /// 위젯용 읽기 전용 저장소. 폴더 만들기·백업 표시·경량 이전 같은 쓰기를 하지 않는다.
  /// 쓰기 호출은 `.failed` 로 던진다. 파일이 없거나 이전 전 스키마(앱이 아직 열지 않은 업데이트 직후)면 `.failed`.
  init(readingAt url: URL) throws(PhotoStoreError) {
    try self.init(configuration: ModelConfiguration(url: url, allowsSave: false, cloudKitDatabase: .none))
  }
}

extension PhotoStoreClientImpl {
  /// Tuist `Env.appGroupInfoKey` 와 같은 값. App Group 이름은 Info.plist 로 받는다.
  static let appGroupInfoKey = "SnapSortAppGroupIdentifier"
  static let folderName = "PhotoStore"
  static let fileName = "PhotoStore.store"
  /// group 폴더와 같은 디렉터리에 둬야 rename 이 원자적이다.
  static let movingFolderName = "PhotoStore.moving"

  static func storeURL(in folder: URL) -> URL {
    folder.appending(path: self.fileName)
  }

  private static func exists(_ url: URL, _ fileManager: FileManager) -> Bool {
    fileManager.fileExists(atPath: url.path(percentEncoded: false))
  }
}
