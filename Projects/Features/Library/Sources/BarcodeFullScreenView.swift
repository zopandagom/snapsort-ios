import Core
import DesignSystem
import SwiftUI

/// 기프티콘 바코드 크게 보기 (docs/ARCHITECTURE.md §4 캡처 정보 추출). 매장 스캐너가 읽기 쉽게 흰 바탕에 크게 그리고, 보이는 동안 화면 밝기를 최대로 둔다.
/// 다시 그린 바코드(QR·Code128·PDF417·Aztec, 내용이 ASCII)는 픽셀을 보간하지 않고 확대하고, 원본에서 자른 영역은 부드럽게 확대한다.
/// 아래에 바코드 내용을 글자로 보인다(복사 버튼은 두지 않는다). 내용은 로그에 남기지 않는다.
struct BarcodeFullScreenView: View {
  let barcode: BarcodeState
  let onClose: () -> Void

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Color.white
        .ignoresSafeArea()
      if case let .found(image, payload) = self.barcode {
        VStack(spacing: 24) {
          Image(decorative: image.cgImage, orientation: image.orientation)
            .interpolation(image.isRedrawn ? .none : .high)
            .resizable()
            .scaledToFit()
            .padding(.horizontal, 24)
            .accessibilityLabel(Text("바코드"))
          Text(payload)
            .font(.title3.monospaced())
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        // 크게 보는 동안 바코드가 사라졌다(기프티콘에서 빠짐 등).
        Text("바코드를 보일 수 없습니다")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      Button("닫기", action: self.onClose)
        .buttonStyle(.bordered)
        .padding()
    }
    .foregroundStyle(.black)
    // 흰 바탕에 맞춰 다크 모드에서도 밝은 모양으로 그린다.
    .environment(\.colorScheme, .light)
    .screenBrightnessMaximized()
  }
}
