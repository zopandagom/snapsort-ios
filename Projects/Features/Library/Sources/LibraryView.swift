import Core
import SwiftUI

/// Model 은 App 이 소유하고 주입한다. @Observable 이므로 View 는 참조만 들고 있어도 변경을 관찰한다.
public struct LibraryView: View {
  let model: LibraryModel

  public init(model: LibraryModel) {
    self.model = model
  }

  public var body: some View {
    NavigationStack {
      List {
        self.indexingSection
        // 덮는 overlay 로 두면 위의 진행률·다시 시도를 가리므로 목록 안에 둔다.
        if self.model.categoryCounts.isEmpty {
          Section {
            ContentUnavailableView(
              "이미지 \(self.model.imageCount)장",
              systemImage: "photo.stack",
              description: Text(self.emptyDescription)
            )
          }
        }
        self.categorySection("캡처", group: .information)
        self.categorySection("사진", group: .photo)
        self.categorySection("기타", group: .other)
      }
      .navigationTitle("SnapSort")
      .safeAreaInset(edge: .top) {
        if self.model.isLimited {
          self.limitedAccessBanner
        }
      }
    }
    .task { await self.model.onAppear() }
  }

  private var emptyDescription: String {
    if self.model.isIndexing {
      "이미지를 분류하는 중입니다."
    } else {
      "분류된 이미지가 없습니다."
    }
  }

  /// 분석 중일 때와 멈췄을 때만 보인다. 정상으로 다 분석하면 숨기되, 미룬 이미지가 있으면 그 수는 남겨 안내한다.
  /// `isFinished` 는 미룬 수까지 더해 판단하므로, 숨기기만 하면 iCloud 에만 있는 사진처럼 분류되지 않은 이유가 사라진다.
  /// 첫 진행률을 받기 전에 멈출 수도 있으므로(저장소 실패 등), 멈춤 안내는 진행률이 없어도 띄운다.
  /// 첫 진행률은 보관함과 저장소 비교를 마친 뒤에 오므로, 그 전에는 준비 중으로 보여 준다.
  @ViewBuilder
  private var indexingSection: some View {
    if self.model.isIndexingStopped {
      Section {
        HStack {
          Label(self.stoppedText, systemImage: "exclamationmark.triangle")
            .font(.subheadline)
          Spacer()
          Button("다시 시도") {
            self.model.retryIndexingTapped()
          }
          .buttonStyle(.bordered)
          .font(.subheadline)
        }
      }
    } else if let progress = self.model.indexingProgress, !progress.isFinished {
      let doneCount = progress.indexedCount + progress.skippedCount
      Section {
        ProgressView(value: Double(doneCount), total: Double(max(progress.totalCount, 1))) {
          Text("이미지 분류 중")
        } currentValueLabel: {
          Text("\(doneCount)/\(progress.totalCount)장")
        }
      } footer: {
        if progress.skippedCount > 0 {
          Text("읽지 못한 \(progress.skippedCount)장은 다음에 다시 시도합니다.")
        }
      }
    } else if self.model.isIndexing {
      Section {
        HStack(spacing: 12) {
          ProgressView()
          Text("이미지 분류 준비 중")
        }
      }
    } else if let progress = self.model.indexingProgress, progress.skippedCount > 0 {
      Section {
        Label(
          "읽지 못한 \(progress.skippedCount)장은 다음에 다시 시도합니다",
          systemImage: "icloud.slash"
        )
        .font(.subheadline)
      } footer: {
        Text("iCloud 에만 있거나 읽을 수 없는 사진입니다.")
      }
    }
  }

  /// 다 분석한 뒤 증분 반영 중에 멈추면 마지막 진행률이 n/n 이므로, 개수 대신 새 사진을 분류하지 못했다고 안내한다.
  private var stoppedText: String {
    guard let progress = self.model.indexingProgress else { return "분류를 마치지 못했습니다" }
    if progress.isFinished {
      return "새 사진을 분류하지 못했습니다"
    }
    return "분류를 마치지 못했습니다 (\(progress.indexedCount + progress.skippedCount)/\(progress.totalCount))"
  }

  /// 이미지가 있는 카테고리만 보여 주고, 하나도 없으면 섹션째 숨긴다.
  @ViewBuilder
  private func categorySection(_ title: String, group: ImageCategoryGroup) -> some View {
    let rows = ImageCategory.allCases.compactMap { category in
      self.model.categoryCounts[category].map { (category: category, count: $0) }
    }
    .filter { $0.category.group == group }
    if !rows.isEmpty {
      Section {
        ForEach(rows, id: \.category) { row in
          LabeledContent {
            Text(row.category.countText(row.count))
          } label: {
            Label(row.category.title, systemImage: row.category.systemImage)
          }
        }
      } header: {
        Text(title)
      } footer: {
        // 여행은 고른 사진만으로 판정하므로 제한 접근이면 실제 여행과 다를 수 있다 (docs/ARCHITECTURE.md §4 여행 판정).
        if group == .photo, self.model.isLimited, self.model.categoryCounts[.travel] != nil {
          Text("선택한 사진만으로 여행을 찾아 정확하지 않을 수 있습니다.")
        }
      }
    }
  }

  private var limitedAccessBanner: some View {
    HStack(spacing: 12) {
      Label("선택한 사진만 분류합니다", systemImage: "photo.badge.checkmark")
        .font(.subheadline)
      Spacer()
      Button("사진 더 선택") {
        Task { await self.model.selectMorePhotosTapped() }
      }
      .buttonStyle(.bordered)
      .font(.subheadline)
    }
    .padding()
    .background(.thinMaterial, in: .rect(cornerRadius: 12))
    .padding(.horizontal)
  }
}

/// 화면에 보이는 이름과 아이콘. Core 는 SwiftUI·문구를 갖지 않으므로 화면 쪽에 둔다.
extension ImageCategory {
  var title: String {
    switch self {
    case .gifticon: "기프티콘"
    case .receipt: "영수증"
    case .chat: "대화 캡처"
    case .shopping: "쇼핑"
    case .map: "지도"
    case .document: "문서·메모"
    case .travel: "여행"
    case .food: "음식"
    case .people: "인물"
    case .pet: "반려동물"
    case .landscape: "풍경"
    case .other: "기타"
    }
  }

  var systemImage: String {
    switch self {
    case .gifticon: "gift"
    case .receipt: "receipt"
    case .chat: "bubble.left.and.bubble.right"
    case .shopping: "bag"
    case .map: "map"
    case .document: "doc.text"
    case .travel: "airplane"
    case .food: "fork.knife"
    case .people: "person.2"
    case .pet: "pawprint"
    case .landscape: "mountain.2"
    case .other: "square.grid.2x2"
    }
  }

  /// 여행은 이미지 수가 아니라 여행 수를 센다 (`LibraryModel.categoryCounts`).
  func countText(_ count: Int) -> String {
    self == .travel ? "\(count)번" : "\(count)장"
  }
}
