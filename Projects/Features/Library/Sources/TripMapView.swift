import Core
import MapKit
import SwiftUI

/// 여행 폴더 상세의 고정 지도. 반올림 중심점에 핀 하나만 꽂는다 (docs/ARCHITECTURE.md §4 위치·지도).
/// 지도 타일을 받으려고 Apple 지도 서비스로 가는 값은 보이는 영역뿐이다(CLAUDE.md "지도 표시" 예외). 사진마다 핀을 꽂지 않는다.
/// Feature 에서 MapKit 을 import 하는 파일은 이것 하나다.
struct TripMapView: View {
  let center: Coordinate

  var body: some View {
    let coordinate = CLLocationCoordinate2D(latitude: self.center.latitude, longitude: self.center.longitude)
    Map(
      initialPosition: .region(MKCoordinateRegion(
        center: coordinate,
        span: MKCoordinateSpan(latitudeDelta: Self.span, longitudeDelta: Self.span)
      )),
      interactionModes: []
    ) {
      Marker("여행지", systemImage: ImageCategory.travel.systemImage, coordinate: coordinate)
    }
    // 처음 위치만 받으므로, 중심점이 바뀌면(판정이 바뀜) 새 지도로 다시 그린다.
    .id(self.center)
    .frame(height: 180)
    .clipShape(.rect(cornerRadius: 12))
    .accessibilityLabel(Text("여행지 지도"))
  }

  /// 도시 하나가 들어오는 넓이(위도 약 0.5도).
  private static let span: CLLocationDegrees = 0.5
}
