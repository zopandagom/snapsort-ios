import ProjectDescription

// 모듈 이름의 단일 출처. 새 모듈은 여기에 case 를 추가한 뒤 Projects/ 아래에 매니페스트를 만든다.
// 규칙은 docs/ARCHITECTURE.md 의 "모듈 추가" 절 참고.

/// 외부 시스템(PhotoKit, Vision, Foundation Models, SwiftData 등)을 감싸는 Client 모듈.
/// 각 Client 는 Interface / Impl / Testing / Tests 네 타깃으로 나뉜다.
public enum Client: String, CaseIterable {
  case photoLibrary = "PhotoLibrary"

  public var interface: String { "\(self.rawValue)Interface" }
  public var impl: String { "\(self.rawValue)Impl" }
  public var testing: String { "\(self.rawValue)Testing" }
  public var tests: String { "\(self.rawValue)Tests" }
  var path: Path { .relativeToRoot("Projects/Clients/\(self.rawValue)") }
}

/// 화면 단위 기능 모듈. Feature 끼리는 서로 의존하지 않는다.
/// 각 Feature 는 Feature / Tests / Example 세 타깃으로 나뉜다.
public enum Feature: String, CaseIterable {
  case library = "Library"
  case onboarding = "Onboarding"

  public var name: String { "\(self.rawValue)Feature" }
  public var tests: String { "\(self.name)Tests" }
  public var example: String { "\(self.name)Example" }
  var path: Path { .relativeToRoot("Projects/Features/\(self.rawValue)") }
}

/// 여러 모듈이 함께 쓰는 공용 모듈 (도메인 값 타입, 공용 UI). Apple 데이터 프레임워크와 Client 에 의존하지 않는다.
/// 각 Shared 모듈은 모듈 / Tests 두 타깃으로 나뉜다.
public enum Shared: String, CaseIterable {
  case core = "Core"

  public var name: String { self.rawValue }
  public var tests: String { "\(self.rawValue)Tests" }
  var path: Path { .relativeToRoot("Projects/Shared/\(self.rawValue)") }
}

public extension TargetDependency {
  static func client(interface client: Client) -> TargetDependency {
    .project(target: client.interface, path: client.path)
  }

  /// Impl 은 App(조립 지점)만 의존한다.
  static func client(impl client: Client) -> TargetDependency {
    .project(target: client.impl, path: client.path)
  }

  /// Testing 은 테스트 타깃과 Example 앱만 의존한다.
  static func client(testing client: Client) -> TargetDependency {
    .project(target: client.testing, path: client.path)
  }

  static func shared(_ shared: Shared) -> TargetDependency {
    .project(target: shared.name, path: shared.path)
  }

  static func feature(_ feature: Feature) -> TargetDependency {
    .project(target: feature.name, path: feature.path)
  }
}
