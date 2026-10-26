// Debug 전용: SampleRecorderModel.swift 머리 주석 참고
#if DEBUG
  import Core
  import Foundation
  import PhotoLibraryInterface

  /// 샘플 보기 상태. 사진은 화면에만 보이고 파일·공유를 만들지 않는다 (docs/CONVENTIONS.md §4).
  public enum SamplePreview: Sendable {
    case idle
    /// 권한 확인·보관함 조회 중. 아직 행이 없다.
    case fetching
    /// 입력·권한 실패. 행 없이 문구 하나.
    case failed(SamplePreviewFailure)
    case list(SampleList)
  }

  /// 입력한 번호들의 행. 입력 순서이고 번호는 겹치지 않는다.
  public struct SampleList: Sendable {
    /// 조회 시점 보관함 장수. 측정 파일의 `libraryCount` 와 비교해 번호가 밀렸는지 본다.
    public let libraryCount: Int
    /// Model 만 바꾼다 (같은 모듈).
    public internal(set) var rows: [SampleRow]

    /// footer 의 "읽음". View 에서 세지 않고 여기서 계산해 테스트로 확인한다.
    public var loadedCount: Int {
      self.rows.count {
        if case .loaded = $0.state {
          true
        } else {
          false
        }
      }
    }

    public var failedCount: Int {
      self.rows.count {
        if case .failed = $0.state {
          true
        } else {
          false
        }
      }
    }
  }

  public struct SampleRow: Sendable, Identifiable {
    /// 최신순 1부터. 보관함 전체 정확도 샘플 이름 `보관함 00001` 과 같은 기준이다. 겹치지 않으므로 식별자로 쓴다.
    public let number: Int
    /// 범위 밖이면 nil.
    public let creationDate: Date?
    public internal(set) var state: SampleRowState

    public var id: Int {
      self.number
    }
  }

  public enum SampleRowState: Sendable {
    case loading
    case loaded(AnalysisImage)
    case failed(SampleRowFailure)
  }

  /// 절 전체의 실패. 조회·읽기 전에 난다.
  public enum SamplePreviewFailure: Error, Equatable {
    case input(SampleNumberFailure)
    case notAuthorized
    /// 고른 사진만 보여 번호가 기록과 달라진다.
    case limitedAccess
  }

  /// 번호 목록 입력의 실패(`SampleLookup.numbers(from:)`). 샘플 보기와 번호로 기록 모드가 함께 쓴다.
  public enum SampleNumberFailure: Error, Equatable {
    /// 빈 입력(구분자만 있는 입력 포함).
    case noNumbers
    /// 1 이상의 정수가 아닌 토큰. 입력 순서.
    case invalidTokens([String])
    /// 중복을 없앤 뒤 개수가 상한을 넘었다.
    case tooMany(count: Int)
  }

  /// 그 행만의 실패. 다음 행은 계속 읽는다.
  public enum SampleRowFailure: Sendable, Equatable {
    /// 번호가 보관함 장수보다 크다. 읽지 않는다.
    case outOfRange
    /// 조회와 읽기 사이에 지워졌다.
    case notFound
    case notAvailableLocally
    /// 읽기 실패, 그리고 요청이 그대로인데 온 취소(PhotoKit 이 스스로 보고한 경우).
    case loadFailed
  }

  /// 번호 목록 → 지금 보관함의 사진. 보기마다 보관함을 한 번 조회하고 캐시하지 않는다
  /// (기록 시점 목록은 남지 않아 캐시해도 번호 밀림은 그대로다). 번호로 기록 모드도 같은 번호 해석(`numbers(from:)`)을 쓴다.
  struct SampleLookup: Sendable {
    enum LibraryOutcome: Sendable {
      case ready([ImageAsset])
      case failed(SamplePreviewFailure)
      case cancelled
    }

    enum RowOutcome: Sendable {
      case loaded(AnalysisImage)
      case failed(SampleRowFailure)
      case cancelled

      /// 요청 번호가 그대로일 때 행에 넣을 상태. 그때 온 취소는 PhotoKit 이 스스로 보고한 것이라 읽기 실패로 보이고 다음 행은 계속 읽는다.
      var rowState: SampleRowState {
        switch self {
        case let .loaded(image): .loaded(image)
        case let .failed(failure): .failed(failure)
        case .cancelled: .failed(.loadFailed)
        }
      }
    }

    /// 썸네일 한 장 디코딩이 약 1MB 라 100장이면 약 100MB 다. 번호로 기록도 한 입력을 보기·기록에 그대로 쓰도록 같은 상한을 쓴다.
    static let maxCount = 100

    let photoLibrary: any PhotoLibraryClient

    /// 쉼표·공백·줄바꿈으로 나누고 빈 토큰을 버린 뒤, 잘못된 토큰 → 빈 입력 → 중복 제거 → 상한 순서로 판정한다.
    /// 토큰은 ASCII 숫자만, 1 이상, 앞자리 0 허용("007" → 7). 중복은 처음 나온 것만 남기고 입력 순서를 지킨다.
    /// 샘플 보기와 번호로 기록 모드가 함께 쓴다.
    static func numbers(from input: String) -> Result<[Int], SampleNumberFailure> {
      let tokens = input.split { $0 == "," || $0.isWhitespace }.map(String.init)
      var numbers: [Int] = []
      var invalidTokens: [String] = []
      for token in tokens {
        if token.allSatisfy(\.isASCIIDigit), let number = Int(token), number >= 1 {
          numbers.append(number)
        } else {
          invalidTokens.append(token)
        }
      }
      guard invalidTokens.isEmpty else { return .failure(.invalidTokens(invalidTokens)) }
      guard !numbers.isEmpty else { return .failure(.noNumbers) }
      var seen = Set<Int>()
      let unique = numbers.filter { seen.insert($0).inserted }
      guard unique.count <= self.maxCount else { return .failure(.tooMany(count: unique.count)) }
      return .success(unique)
    }

    /// 권한 → 조회. 권한 기준은 보관함 전체 정확도 기록과 같고, 권한 팝업은 띄우지 않는다.
    @concurrent
    func fetchLibrary() async -> LibraryOutcome {
      switch self.photoLibrary.accessState() {
      case .authorized:
        break
      case .limited:
        return .failed(.limitedAccess)
      case .denied, .notDetermined, .restricted:
        return .failed(.notAuthorized)
      }
      let library = await self.photoLibrary.fetchImageAssets()
      // 조회는 취소에 반응하지 않을 수 있어, 끝난 뒤 확인해 읽기를 건너뛴다.
      guard !Task.isCancelled else { return .cancelled }
      return .ready(library)
    }

    /// 썸네일 한 장. `.cancelled` 는 그대로 돌려 Model 이 요청 번호로 판단한다.
    @concurrent
    func loadThumbnail(id: ImageAsset.ID) async -> RowOutcome {
      do {
        return try await .loaded(self.photoLibrary.loadImage(id: id, size: .thumbnail))
      } catch {
        switch error {
        case .cancelled: return .cancelled
        case .notFound: return .failed(.notFound)
        case .notAvailableLocally: return .failed(.notAvailableLocally)
        case .failed: return .failed(.loadFailed)
        }
      }
    }
  }

  fileprivate extension Character {
    /// `isNumber` 는 전각·아라비아 숫자도 받으므로 ASCII 숫자만 고른다.
    var isASCIIDigit: Bool {
      self.isASCII && self.isWholeNumber
    }
  }
#endif
