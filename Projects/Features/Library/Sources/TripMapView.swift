import Core
import DesignSystem
import MapKit
import SwiftUI

/// 여행 폴더 상세의 지도. 반올림 중심점에 핀 하나만 꽂고, 사용자가 끌기·확대로 둘러볼 수 있다 (docs/ARCHITECTURE.md §4 위치·지도).
/// 지도 타일을 받으려고 Apple 지도 서비스로 가는 값은 처음 보이는 중심점 주변과, 그 뒤 사용자가 움직인 영역뿐이다(CLAUDE.md "지도 표시" 예외).
/// 앱이 카메라를 옮기는 곳은 중심점에서 만든 처음 영역 하나다(원위치 버튼·중심점 변경). 사진마다 핀을 꽂지 않는다.
/// Feature 에서 MapKit 을 import 하는 파일은 이것 하나다.
struct TripMapView: View {
  let center: Coordinate

  /// MapKit 카메라에 묶인 이 화면만의 상태(Model 상태 아님). 사용자가 움직이면 `positionedByUser` 인 값으로 바뀐다.
  @State private var position: MapCameraPosition

  init(center: Coordinate) {
    self.center = center
    self._position = State(initialValue: Self.initialPosition(center))
  }

  var body: some View {
    Map(position: self.$position, bounds: Self.bounds, interactionModes: [.pan, .zoom]) {
      Marker("여행지", systemImage: ImageCategory.travel.systemImage, coordinate: Self.coordinate(self.center))
    }
    // 판정이 바뀌어 중심점이 달라지면 새 중심점의 처음 영역으로 옮긴다.
    .onChange(of: self.center) { _, center in
      self.position = Self.initialPosition(center)
    }
    .frame(height: 240)
    .clipShape(.rect(cornerRadius: 12))
    .accessibilityLabel(Text("여행지 지도"))
    .overlay(alignment: .topTrailing) {
      if self.position.positionedByUser {
        self.recenterButton
          .transition(.opacity)
      }
    }
  }

  /// 움직인 지도를 처음 영역(반올림 중심점 주변)으로 되돌린다.
  private var recenterButton: some View {
    Button {
      withAnimation {
        self.position = Self.initialPosition(self.center)
      }
    } label: {
      Image(systemName: "scope")
        .font(.body.weight(.semibold))
        .foregroundStyle(SnapColor.accent)
        .frame(width: 44, height: 44)
        .background(.regularMaterial, in: .circle)
        .contentShape(.circle)
    }
    .buttonStyle(.plain)
    .padding(8)
    .accessibilityLabel("여행지로 돌아가기")
  }

  private static func coordinate(_ center: Coordinate) -> CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
  }

  private static func initialPosition(_ center: Coordinate) -> MapCameraPosition {
    .region(MKCoordinateRegion(
      center: self.coordinate(center),
      span: MKCoordinateSpan(latitudeDelta: self.span, longitudeDelta: self.span)
    ))
  }

  /// 처음 넓이: 동네가 들어오는 넓이(위도 약 0.05도, 약 5.5km). 반올림 오차(약 1km)보다 충분히 넓게 둔다.
  private static let span: CLLocationDegrees = 0.05

  /// 가장 가까이 확대할 때의 카메라 거리(m, 임시 값. 실기기에서 맞춘다).
  /// 핀은 약 1km 로 반올림한 중심점이라, 거리 이름까지 확대하면 정확한 촬영 위치처럼 보이므로 막는다(개인정보 장치가 아니라 오해 방지).
  /// 축소·이동 범위는 막지 않는다: 다른 곳의 타일은 사용자가 움직일 때만 요청된다.
  private static let bounds = MapCameraBounds(minimumDistance: 3000)
}
