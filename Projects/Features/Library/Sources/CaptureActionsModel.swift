import Core
import Foundation
import ImageAnalysisInterface
import MapInterface
import Observation
import PasteboardInterface
import PhotoStoreInterface

/// 사진 상세의 캡처 행동 (docs/ARCHITECTURE.md §4 카테고리 화면·캡처 정보 추출).
/// 저장된 OCR 줄에서 찾은 주소(지도 앱 열기)·송장·계좌번호(복사)와, 기프티콘 목록에서 연 상세의 기프티콘 정보·사용함 전환·바코드 크게 보기를 맡는다.
/// 상세는 한 번에 하나만 열리므로 App 이 하나를 소유하고, 열 때마다 `detailAppeared(id:gifticon:)` 로 다시 쓴다.
/// 바코드는 상세에 띄운 이미지(`CategoryModel.detail`)로 찾으므로, 이미지를 읽으면 PhotoDetailView 가 `detailImageLoaded(_:id:)` 로 넘긴다.
/// 사용 여부를 쓰면 `usageRevision` 이 오르고 LibraryView 가 알림 동기화·목록 다시 읽기로 넘긴다(Model 끼리 참조하지 않는다).
/// 주소·번호·바코드 내용은 사진에서 읽은 텍스트이므로 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
@MainActor
@Observable
public final class CaptureActionsModel {
  /// 열린 상세의 식별자. 닫히면 nil.
  public private(set) var detailID: ImageAsset.ID?
  /// 열린 상세의 요청 번호. 상세를 열 때마다 바뀌고 닫히면 nil 이다. 같은 사진을 닫았다 바로 다시 열어도 바뀌므로,
  /// View 가 바코드 인식 `.task(id:)` 의 키로 써서 새 상세에서 다시 돈다. 닫힌 뒤 끝난 작업이 상태를 바꾸지 않게 하는 데도 쓴다.
  public private(set) var detailRequest: Int?
  /// 기프티콘 목록에서 연 상세만 값이 있다. 다시 읽어 기프티콘이 아니게 되면 nil.
  public private(set) var gifticon: GifticonListItem?
  /// 상세의 D-n·만료일 표시 기준. 기기 시간대의 오늘. `detailAppeared`·`dayChanged()` 때 다시 계산한다.
  public private(set) var today: LocalDate
  /// 만료일 표시가 쓰는 기기 달력의 사본. 시간대가 바뀌면 다시 그려지게 `GifticonListModel.calendar` 와 같은 규칙으로 담는다.
  public private(set) var calendar: Calendar
  /// 저장된 OCR 줄에서 찾은 주소·번호.
  public private(set) var captureInfo: CaptureInfoState = .loading
  public private(set) var barcode: BarcodeState = .notApplicable
  /// 사용 여부를 쓰는 동안 참. 버튼을 막아 두 번 쓰지 않게 한다.
  public private(set) var isUpdatingUsage = false
  /// 사용 여부를 저장소에 쓸 때마다 오른다(화면이 닫힌 뒤 끝난 쓰기도). LibraryView 가 알림 동기화·목록 다시 읽기로 넘긴다.
  public private(set) var usageRevision = 0
  public private(set) var alert: CaptureActionAlert?
  /// 마지막으로 복사한 값. 화면이 "복사했습니다"를 잠깐 보인다.
  public private(set) var copied: CopiedNotice?

  /// 상세를 열 때마다 하나씩 올린다. 닫은 뒤 바로 다른(또는 같은) 사진을 열어도 지난 Task 가 지금 상세를 바꾸지 않게 한다.
  @ObservationIgnored private var detailRequestCount = 0
  /// 기프티콘을 다시 읽으라는 신호. 상세가 열려 있는 동안만 있다.
  @ObservationIgnored private var reloadRequests: AsyncStream<Void>.Continuation?
  /// 사용 여부 쓰기를 시작할 때마다 오른다. 쓰기 전에 시작한 다시 읽기가 쓴 값을 옛 값으로 되돌리지 않게 한다.
  @ObservationIgnored private var usageWriteCount = 0
  @ObservationIgnored private var copyCount = 0

  @ObservationIgnored private let photoStore: (any PhotoStoreClient)?
  @ObservationIgnored private let imageAnalysis: any ImageAnalysisClient
  @ObservationIgnored private let map: any MapClient
  @ObservationIgnored private let pasteboard: any PasteboardClient
  @ObservationIgnored private let currentCalendar: @Sendable () -> Calendar
  @ObservationIgnored private let now: @Sendable () -> Date

  /// - Parameters:
  ///   - photoStore: 저장된 OCR 줄과 기프티콘을 읽고 사용 여부를 쓰는 저장소. App 이 저장소를 열지 못하면 nil 이다(행동 버튼이 없다).
  ///   - imageAnalysis: 상세 이미지의 바코드 인식.
  ///   - map: 주소를 지도 앱으로 넘긴다. 사용자가 누를 때만 부른다.
  ///   - pasteboard: 번호를 이 기기에서만 붙여 넣을 수 있게 복사한다.
  ///   - calendar: 기기 달력. 상세를 열 때와 `dayChanged()` 때 부른다.
  ///   - now: 지금 시각. 상세를 열 때와 `dayChanged()` 때 부른다.
  public init(
    photoStore: (any PhotoStoreClient)?,
    imageAnalysis: any ImageAnalysisClient,
    map: any MapClient,
    pasteboard: any PasteboardClient,
    calendar: @escaping @Sendable () -> Calendar = { .current },
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.photoStore = photoStore
    self.imageAnalysis = imageAnalysis
    self.map = map
    self.pasteboard = pasteboard
    self.currentCalendar = calendar
    self.now = now
    let current = calendar()
    self.calendar = current
    self.today = LocalDate(now(), calendar: current)
  }

  // MARK: - Events

  /// 상세가 열렸다. 저장된 OCR 줄에서 주소·번호를 찾고, 닫힐 때까지(View 의 `.task` 수명) 기프티콘 다시 읽기 신호를 기다린다.
  /// 닫히면 자기 요청일 때만 모든 상태를 지운다(바코드 이미지도 놓는다).
  /// - Parameter gifticon: 기프티콘 목록에서 열었으면 그 항목. 이때만 기프티콘 정보·사용함 버튼·바코드를 보인다.
  public func detailAppeared(id: ImageAsset.ID, gifticon: GifticonListItem?) async {
    self.detailRequestCount += 1
    let request = self.detailRequestCount
    self.detailRequest = request
    self.detailID = id
    self.gifticon = gifticon
    self.barcode = gifticon == nil ? .notApplicable : .waitingForImage
    self.captureInfo = .loading
    self.isUpdatingUsage = false
    self.alert = nil
    self.copied = nil
    self.refreshDay()
    let (requests, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    self.reloadRequests = continuation

    if let photoStore = self.photoStore {
      await self.loadCaptureInfo(id: id, photoStore: photoStore, request: request)
      // 기프티콘 목록에서 연 상세만 기프티콘을 다시 읽는다. 그 밖의 상세는 신호를 기다리기만 한다.
      for await _ in requests where gifticon != nil {
        guard self.isCurrent(request) else { break }
        await self.reloadGifticon(id: id, photoStore: photoStore, request: request)
      }
    } else {
      self.captureInfo = .unavailable
      for await _ in requests {}
    }
    // 닫혔다.
    self.clear(request: request)
  }

  /// 상세 이미지를 읽었다. 기프티콘 상세이고 바코드를 아직 찾지 않았으면 그 이미지로 찾는다.
  /// View 가 `.task(id:)` 에서 부르므로 상세를 닫으면 인식이 취소되고, 다시 열면 다시 찾는다.
  public func detailImageLoaded(_ image: AnalysisImage, id: ImageAsset.ID) async {
    guard let request = self.detailRequest, self.detailID == id, self.barcode == .waitingForImage else { return }
    self.barcode = .detecting
    let barcodes: [DetectedBarcode]
    do throws(ImageAnalysisError) {
      barcodes = try await self.imageAnalysis.detectBarcodes(image)
    } catch {
      guard self.isCurrent(request), self.barcode == .detecting else { return }
      self.barcode = error == .cancelled ? .waitingForImage : .failed
      return
    }
    guard self.isCurrent(request), self.barcode == .detecting else { return }
    // 큰 것부터 오므로 첫 바코드가 기프티콘 바코드다.
    guard let first = barcodes.first else {
      self.barcode = .notFound(isLocalFallback: image.isLocalFallback)
      return
    }
    // 그리기는 취소되지 않으므로, 돌아온 뒤 같은 규칙으로 버린다.
    let rendered = await BarcodeRendering.image(for: first, in: image)
    guard self.isCurrent(request), self.barcode == .detecting else { return }
    guard !Task.isCancelled else {
      self.barcode = .waitingForImage
      return
    }
    self.barcode = rendered.map { .found($0, payload: first.payload) } ?? .failed
  }

  /// 상세 이미지를 볼 수 없다(iCloud 에만 있음 등). 기프티콘 상세면 바코드를 찾을 수 없다고 보인다.
  public func detailImageUnavailable(id: ImageAsset.ID) {
    guard self.detailRequest != nil, self.detailID == id, self.barcode == .waitingForImage else { return }
    self.barcode = .imageUnavailable
  }

  /// 저장소 내용이 바뀌었을 수 있다는 신호. 기프티콘 상세가 열려 있으면 기프티콘을 다시 읽는다.
  public func libraryStoreChanged() {
    self.reloadRequests?.yield()
  }

  /// 사용함 ↔ 미사용을 바꾼다. 쓰기가 끝나면 화면이 닫혔어도 `usageRevision` 을 올려 만료 알림을 다시 맞추게 한다.
  public func usedButtonTapped() async {
    guard let request = self.detailRequest, let gifticon = self.gifticon, !self.isUpdatingUsage,
          let photoStore = self.photoStore
    else { return }
    self.isUpdatingUsage = true
    self.usageWriteCount += 1
    let isUsed = !gifticon.isUsed
    do throws(PhotoStoreError) {
      if try await photoStore.setGifticonUsed(isUsed, id: gifticon.id) {
        self.usageRevision += 1
        if self.isCurrent(request) {
          self.gifticon = self.gifticon?.with(isUsed: isUsed)
        }
      } else if self.isCurrent(request) {
        // 그사이 기프티콘이 아니게 됐다. 다시 읽어 기프티콘 영역을 거둔다.
        self.reloadRequests?.yield()
      }
    } catch {
      if self.isCurrent(request) {
        self.alert = .usageUpdateFailed
        // 쓰는 동안 버린 다시 읽기가 있었을 수 있다.
        self.reloadRequests?.yield()
      }
    }
    if self.isCurrent(request) {
      self.isUpdatingUsage = false
    }
  }

  /// 주소를 지도 앱으로 넘긴다(사용자가 눌렀을 때만). 앱은 주소를 지오코딩하지 않는다.
  /// 열지 못했다는 결과가 누른 상세가 닫힌 뒤(다른 사진이나 같은 사진을 다시 연 뒤 포함) 오면 버린다.
  public func addressTapped(_ address: CapturedText) async {
    let request = self.detailRequest
    let opened = await self.map.openInMaps(address: address.text)
    if !opened, let request, self.isCurrent(request) {
      self.alert = .mapsUnavailable
    }
  }

  /// 송장·계좌번호를 이 기기에서만 붙여 넣을 수 있게 복사한다. 복사는 늘 하고, 누른 상세가 닫힌 뒤
  /// (다른 사진이나 같은 사진을 다시 연 뒤 포함) 끝나면 복사 안내는 띄우지 않는다.
  public func numberCopyTapped(_ number: CapturedText) async {
    let request = self.detailRequest
    await self.pasteboard.copy(number.text)
    guard let request, self.isCurrent(request) else { return }
    self.copyCount += 1
    self.copied = CopiedNotice(number: number, count: self.copyCount)
  }

  public func alertDismissed() {
    self.alert = nil
  }

  /// 날짜나 시간대가 바뀌었다. 열린 상세의 D-n 이 바뀐다. 저장소는 읽지 않는다.
  public func dayChanged() {
    self.refreshDay()
  }

  // MARK: - Private

  /// 줄 없음(OCR 대상 아님·대기)·행 없음은 빈 결과, 저장소 실패는 `.unavailable`(행동 버튼 없음).
  private func loadCaptureInfo(id: ImageAsset.ID, photoStore: any PhotoStoreClient, request: Int) async {
    let lines: [RecognizedTextLine]
    do throws(PhotoStoreError) {
      lines = try await photoStore.images(ids: [id]).first?.textLines ?? []
    } catch {
      guard self.isCurrent(request) else { return }
      self.captureInfo = .unavailable
      return
    }
    guard self.isCurrent(request) else { return }
    let info = await CaptureInfoExtraction.extract(from: lines)
    guard self.isCurrent(request) else { return }
    self.captureInfo = .loaded(info)
  }

  /// 읽지 못하면 지난 값을 둔다. 쓰는 중이거나 읽는 동안 쓰기가 시작됐으면 결과를 버린다: 쓰는 중이면 쓰기가 끝난 뒤의 신호가
  /// 다시 읽게 하고, 읽는 동안 쓰기가 끝났으면 바로 한 번 더 읽는다.
  private func reloadGifticon(id: ImageAsset.ID, photoStore: any PhotoStoreClient, request: Int) async {
    while true {
      let writeCount = self.usageWriteCount
      let item: GifticonListItem?
      do throws(PhotoStoreError) {
        item = try await photoStore.gifticon(id: id)
      } catch {
        return
      }
      guard self.isCurrent(request), !self.isUpdatingUsage else { return }
      guard writeCount == self.usageWriteCount else { continue }
      if self.gifticon != item {
        self.gifticon = item
      }
      if item == nil {
        // 기프티콘에서 빠졌다. 바코드 이미지도 놓는다.
        self.barcode = .notApplicable
      }
      return
    }
  }

  private func clear(request: Int) {
    guard self.isCurrent(request) else { return }
    self.detailRequest = nil
    self.reloadRequests = nil
    self.detailID = nil
    self.gifticon = nil
    self.barcode = .notApplicable
    self.captureInfo = .loading
    self.isUpdatingUsage = false
    self.alert = nil
    self.copied = nil
  }

  /// 같으면 대입하지 않아 다시 그리지 않는다.
  private func refreshDay() {
    let calendar = self.currentCalendar()
    let today = LocalDate(self.now(), calendar: calendar)
    if self.calendar != calendar {
      self.calendar = calendar
    }
    if self.today != today {
      self.today = today
    }
  }

  private func isCurrent(_ request: Int) -> Bool {
    self.detailRequest == request
  }
}

/// 줄 디코딩 뒤의 추출과 바코드 그리기를 메인 밖에서 한다. 긴 문서 캡처의 줄이나 큰 이미지 자르기가 화면을 막지 않게 한다.
enum CaptureInfoExtraction {
  @concurrent
  static func extract(from lines: [RecognizedTextLine]) async -> CaptureInfo {
    CaptureInfoExtractor.extract(from: lines)
  }
}

enum BarcodeRendering {
  @concurrent
  static func image(for barcode: DetectedBarcode, in source: AnalysisImage) async -> BarcodeImage? {
    BarcodeImageRenderer.image(for: barcode, in: source)
  }
}

/// 상세의 캡처 정보 읽기 상태.
public enum CaptureInfoState: Equatable {
  case loading
  /// 찾지 못했으면 빈 `CaptureInfo`.
  case loaded(CaptureInfo)
  /// 저장소를 읽지 못했다. 행동 버튼을 보이지 않는다(안내 없음).
  case unavailable
}

/// 기프티콘 상세의 바코드 상태.
public enum BarcodeState: Equatable {
  /// 기프티콘 목록에서 연 상세가 아니다.
  case notApplicable
  /// 상세 이미지를 읽는 중.
  case waitingForImage
  case detecting
  /// 크게 보기 화면에 보인다. `payload` 는 그 화면 아래 글자로만 보인다(로그 없음).
  case found(BarcodeImage, payload: String)
  /// 바코드가 없다. `isLocalFallback` 이면 작은 대체 버전이라 찾지 못했을 수 있다고 안내한다.
  case notFound(isLocalFallback: Bool)
  /// 인식이나 그리기에 실패했다.
  case failed
  /// 상세 이미지를 볼 수 없다(iCloud 에만 있음 등).
  case imageUnavailable
}

/// 상세의 알림창.
public enum CaptureActionAlert: Hashable, Identifiable {
  /// 사용 여부를 저장하지 못했다.
  case usageUpdateFailed
  /// 지도 앱을 열지 못했다.
  case mapsUnavailable

  public var id: Self { self }
}

/// 복사 안내. 같은 번호를 다시 복사해도 바뀌도록 `count` 를 둔다.
public struct CopiedNotice: Hashable {
  public let number: CapturedText
  public let count: Int
}
