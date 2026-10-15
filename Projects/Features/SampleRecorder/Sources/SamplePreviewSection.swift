// Debug 전용: SampleRecorderModel.swift 머리 주석 참고
#if DEBUG
  import ImageIO
  import SwiftUI

  /// 보관함 전체 정확도 샘플의 사진을 번호 목록으로 보는 절. 사진은 화면에만 보인다 (docs/CONVENTIONS.md §4).
  struct SamplePreviewSection: View {
    let model: SampleRecorderModel

    var body: some View {
      Section {
        HStack {
          TextField(
            "번호 (최신순 1부터, 쉼표·공백 구분)",
            text: Binding(get: { self.model.sampleNumberInput }, set: { self.model.sampleNumberInputChanged($0) }),
            axis: .vertical
          )
          .lineLimit(1 ... 4)
          .keyboardType(.numbersAndPunctuation)
          Button("보기") {
            Task { await self.model.sampleShowTapped() }
          }
        }
        .disabled(self.model.isRecording)
        self.content
      } header: {
        Text("샘플 보기")
      } footer: {
        VStack(alignment: .leading, spacing: 4) {
          Text("번호는 지금 보관함의 최신순 순서입니다. 기록 뒤 사진을 추가·삭제했으면 번호가 밀립니다.")
          if case let .list(list) = self.model.samplePreview {
            Text(
              "지금 보관함 \(list.libraryCount.formatted())장 · "
                + "읽음 \(list.loadedCount) / 실패 \(list.failedCount) / 전체 \(list.rows.count)"
            )
          }
        }
      }
    }

    @ViewBuilder
    private var content: some View {
      switch self.model.samplePreview {
      case .idle:
        EmptyView()
      case .fetching:
        HStack(spacing: 12) {
          ProgressView()
          Text("보관함 조회 중")
        }
      case let .failed(failure):
        Label(Self.failureText(failure), systemImage: "exclamationmark.triangle")
      case let .list(list):
        ForEach(list.rows) { row in
          self.rowView(row, libraryCount: list.libraryCount)
        }
      }
    }

    private func rowView(_ row: SampleRow, libraryCount: Int) -> some View {
      VStack(alignment: .leading, spacing: 8) {
        LabeledContent(SampleDraft.librarySampleName(row.number)) {
          if let creationDate = row.creationDate {
            Text(creationDate.formatted(date: .abbreviated, time: .shortened))
          }
        }
        switch row.state {
        case .loading:
          ProgressView()
        case let .loaded(image):
          Image(decorative: image.cgImage, scale: 1, orientation: Image.Orientation(image.orientation))
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 360)
          if image.isLocalFallback {
            Text("iCloud 대체 버전이라 원본보다 작을 수 있습니다")
          }
        case let .failed(failure):
          Label(Self.rowFailureText(failure, libraryCount: libraryCount), systemImage: "exclamationmark.triangle")
        }
      }
    }

    private static func failureText(_ failure: SamplePreviewFailure) -> String {
      switch failure {
      case .noNumbers: "번호를 넣으세요 (쉼표·공백·줄바꿈으로 구분)"
      case let .invalidTokens(tokens):
        "1 이상의 정수가 아닌 값: \(tokens.prefix(5).joined(separator: ", "))"
          + (tokens.count > 5 ? " 외 \(tokens.count - 5)개" : "")
      case let .tooMany(count): "한 번에 \(SampleLookup.maxCount)개까지 볼 수 있습니다 (지금 \(count)개)"
      case .notAuthorized: "사진을 읽을 권한이 없습니다"
      case .limitedAccess: "샘플 보기는 전체 사진 접근에서만 됩니다. 설정에서 전체 접근을 허용하세요"
      }
    }

    private static func rowFailureText(_ failure: SampleRowFailure, libraryCount: Int) -> String {
      switch failure {
      case .outOfRange:
        libraryCount == 0 ? "보관함에 이미지가 없습니다" : "보관함에 이미지가 \(libraryCount.formatted())장뿐입니다"
      case .notFound: "보관함에 없는 사진입니다. 다시 보기를 누르세요"
      case .notAvailableLocally: "기기에 사진이 없고 iCloud 에만 있습니다. 사진 앱에서 받아 둔 뒤 다시 보세요"
      case .loadFailed: "사진을 읽지 못했습니다"
      }
    }
  }

  extension Image.Orientation {
    /// `AnalysisImage` 는 픽셀을 돌리지 않고 방향을 따로 담으므로 그릴 때 같은 이름의 방향으로 옮긴다.
    init(_ orientation: CGImagePropertyOrientation) {
      switch orientation {
      case .up: self = .up
      case .upMirrored: self = .upMirrored
      case .down: self = .down
      case .downMirrored: self = .downMirrored
      case .left: self = .left
      case .leftMirrored: self = .leftMirrored
      case .right: self = .right
      case .rightMirrored: self = .rightMirrored
      @unknown default: self = .up
      }
    }
  }
#endif
