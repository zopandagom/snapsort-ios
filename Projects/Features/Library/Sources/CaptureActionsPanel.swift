import Core
import SwiftUI

/// 사진 상세 아래의 캡처 행동 (docs/ARCHITECTURE.md §4 캡처 정보 추출).
/// 기프티콘 목록에서 열었으면 교환처·만료일·D-n·사용함 버튼·바코드 상태를, 저장된 OCR 줄에서 찾은 주소마다 "지도에서 보기",
/// 송장·계좌번호마다 "복사"를 보인다. 바코드 크게 보기 화면과 복사 안내의 표시 여부는 화면 일시 상태라 이 View 가 갖는다.
struct CaptureActionsPanel: View {
  let model: CaptureActionsModel
  let assetID: ImageAsset.ID

  @State private var isShowingBarcode = false
  @State private var isShowingCopied = false

  var body: some View {
    // 다른 사진의 상태가 남아 있으면 그리지 않는다.
    if self.model.detailID == self.assetID {
      self.panel
    }
  }

  private var panel: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let gifticon = self.model.gifticon {
        self.gifticonSection(gifticon)
      }
      if case let .loaded(info) = self.model.captureInfo {
        self.captureSection(info)
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.bar)
    .overlay(alignment: .top) {
      if self.isShowingCopied {
        Label("복사했습니다", systemImage: "doc.on.doc")
          .font(.subheadline)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(.thinMaterial, in: .capsule)
          .offset(y: -48)
          .transition(.opacity)
      }
    }
    // 복사할 때마다 잠깐 보인다. 다시 복사하면 처음부터 센다.
    .task(id: self.model.copied) {
      guard self.model.copied != nil else { return }
      withAnimation { self.isShowingCopied = true }
      try? await Task.sleep(for: .seconds(1.5))
      guard !Task.isCancelled else { return }
      withAnimation { self.isShowingCopied = false }
    }
    .alert(
      self.model.alert?.title ?? "",
      isPresented: Binding(
        get: { self.model.alert != nil },
        set: { isPresented in
          if !isPresented {
            self.model.alertDismissed()
          }
        }
      ),
      presenting: self.model.alert
    ) { _ in
      Button("확인", role: .cancel) {}
    } message: { alert in
      Text(alert.message)
    }
    .fullScreenCover(isPresented: self.$isShowingBarcode) {
      BarcodeFullScreenView(barcode: self.model.barcode) {
        self.isShowingBarcode = false
      }
    }
  }

  // MARK: - 기프티콘

  @ViewBuilder
  private func gifticonSection(_ gifticon: GifticonListItem) -> some View {
    if case let .extracted(info) = gifticon.status {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          GifticonFieldText(
            info.redemptionPlace.map { Text($0) } ?? Text("교환처 모름"),
            isKnown: info.redemptionPlace != nil,
            isEstimated: gifticon.estimatedFields.contains(.redemptionPlace)
          )
          .font(.headline)
          GifticonFieldText(
            info.expiryDate.map { GifticonExpiryText.date($0, calendar: self.model.calendar) } ?? Text("만료일 모름"),
            isKnown: info.expiryDate != nil,
            isEstimated: gifticon.estimatedFields.contains(.expiryDate)
          )
          .font(.subheadline)
        }
        Spacer()
        if let expiryDate = info.expiryDate {
          GifticonDueBadge(due: GifticonDue(expiryDate: expiryDate, today: self.model.today))
        }
      }
    } else {
      Text("만료일을 확인하는 중입니다")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    HStack {
      self.barcodeView
      Spacer()
      Button(gifticon.isUsed ? "미사용으로 되돌리기" : "사용함으로 표시") {
        Task { await self.model.usedButtonTapped() }
      }
      .buttonStyle(.bordered)
      .disabled(self.model.isUpdatingUsage)
    }
  }

  @ViewBuilder
  private var barcodeView: some View {
    switch self.model.barcode {
    case .notApplicable, .waitingForImage:
      // 이미지를 읽는 동안은 이미지 자리의 진행 표시만 보인다.
      EmptyView()
    case .detecting:
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
        Text("바코드 찾는 중")
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
    case .found:
      Button {
        self.isShowingBarcode = true
      } label: {
        Label("바코드 크게 보기", systemImage: "barcode.viewfinder")
      }
      .buttonStyle(.borderedProminent)
    case let .notFound(isLocalFallback):
      VStack(alignment: .leading, spacing: 2) {
        Text("바코드를 찾지 못했습니다")
        if isLocalFallback {
          Text("작은 버전이라 찾지 못했을 수 있습니다")
            .font(.caption)
        }
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
    case .failed:
      Label("바코드를 읽지 못했습니다", systemImage: "exclamationmark.triangle")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    case .imageUnavailable:
      Text("사진을 볼 수 없어 바코드를 찾을 수 없습니다")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - 주소·번호

  @ViewBuilder
  private func captureSection(_ info: CaptureInfo) -> some View {
    ForEach(info.addresses, id: \.self) { address in
      self.actionRow(address.text, systemImage: "map", buttonTitle: "지도에서 보기") {
        Task { await self.model.addressTapped(address) }
      }
    }
    ForEach(info.trackingNumbers, id: \.self) { number in
      self.actionRow(number.text, systemImage: "shippingbox", buttonTitle: "복사") {
        Task { await self.model.numberCopyTapped(number) }
      }
    }
    ForEach(info.accountNumbers, id: \.self) { number in
      self.actionRow(number.text, systemImage: "banknote", buttonTitle: "복사") {
        Task { await self.model.numberCopyTapped(number) }
      }
    }
  }

  private func actionRow(
    _ text: String,
    systemImage: String,
    buttonTitle: String,
    action: @escaping () -> Void
  ) -> some View {
    HStack {
      Label(text, systemImage: systemImage)
        .font(.subheadline)
        .lineLimit(2)
      Spacer()
      Button(buttonTitle, action: action)
        .buttonStyle(.bordered)
        .font(.subheadline)
    }
  }
}

extension CaptureActionAlert {
  var title: String {
    switch self {
    case .usageUpdateFailed: "사용 여부를 저장하지 못했습니다"
    case .mapsUnavailable: "지도 앱을 열지 못했습니다"
    }
  }

  var message: String {
    switch self {
    case .usageUpdateFailed: "잠시 뒤 다시 시도해 주세요."
    case .mapsUnavailable: "지도 앱이 설치되어 있는지 확인해 주세요."
    }
  }
}
