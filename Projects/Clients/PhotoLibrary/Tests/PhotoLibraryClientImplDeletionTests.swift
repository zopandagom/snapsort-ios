import Foundation
import PhotoLibraryInterface
import Photos
import Testing
@testable import PhotoLibraryImpl

struct PhotoLibraryClientImplDeletionTests {
  @Test(
    "PhotoKit 오류 코드를 삭제 오류로 변환한다",
    arguments: [
      (3072, ImageDeletionError.userCancelled),
      (3310, .notAuthorized),
      (3311, .notAuthorized),
      (3300, .failed),
      (3305, .failed),
    ]
  )
  func mapsPhotosErrorCodes(code: Int, expected: ImageDeletionError) {
    let error = NSError(domain: PHPhotosErrorDomain, code: code)

    #expect(PhotoLibraryClientImpl.deletionError(from: error) == expected)
  }

  @Test("다른 도메인의 오류는 같은 코드여도 실패다")
  func otherDomainIsFailed() {
    #expect(PhotoLibraryClientImpl.deletionError(from: NSError(domain: NSCocoaErrorDomain, code: 3072)) == .failed)
    #expect(PhotoLibraryClientImpl.deletionError(from: CancellationError()) == .failed)
  }

  @Test("찾은 것은 지우고 못 찾은 것은 건너뛴다")
  func plansDeletionAndSkip() {
    let plan = PhotoLibraryClientImpl.deletionPlan(requested: ["a", "b", "c"], found: ["a", "c"])

    #expect(plan.toDelete == ["a", "c"])
    #expect(plan.skipped == ["b"])
  }

  @Test("모두 찾으면 건너뜀이 없고 하나도 못 찾으면 지울 것이 없다")
  func allOrNoneFound() {
    let all = PhotoLibraryClientImpl.deletionPlan(requested: ["a", "b"], found: ["b", "a"])
    let none = PhotoLibraryClientImpl.deletionPlan(requested: ["a", "b"], found: [])

    #expect(all.toDelete == ["a", "b"])
    #expect(all.skipped.isEmpty)
    #expect(none.toDelete.isEmpty)
    #expect(none.skipped == ["a", "b"])
  }

  @Test("요청에 없는 식별자는 무시하고 빈 요청은 빈 계획이다")
  func ignoresUnrequestedAndEmpty() {
    let extra = PhotoLibraryClientImpl.deletionPlan(requested: ["a"], found: ["a", "z"])
    let empty = PhotoLibraryClientImpl.deletionPlan(requested: [], found: ["z"])

    #expect(extra.toDelete == ["a"])
    #expect(extra.skipped.isEmpty)
    #expect(empty.toDelete.isEmpty)
    #expect(empty.skipped.isEmpty)
  }
}
