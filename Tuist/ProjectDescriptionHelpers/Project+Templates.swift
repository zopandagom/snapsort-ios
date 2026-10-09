import ProjectDescription

public enum Env {
  public static let appName = "SnapSort"
  public static let bundleIdPrefix = "com.zopandagom.snapsort"
  public static let destinations: Destinations = [.iPhone]
  /// Foundation Models 가 동작하는 최소 버전.
  public static let deploymentTargets: DeploymentTargets = .iOS("26.0")

  static let baseSettings: SettingsDictionary = [
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
  ]

  static func bundleId(_ name: String) -> String {
    "\(self.bundleIdPrefix).\(name.lowercased())"
  }
}

public extension Project {
  /// 앱 조립 지점. Feature 와 Client Impl 을 모두 알고 있는 유일한 모듈.
  static func app(infoPlist: [String: Plist.Value], dependencies: [TargetDependency]) -> Project {
    Project(
      name: "App",
      options: .options(defaultKnownRegions: ["ko", "en"], developmentRegion: "ko"),
      settings: .settings(base: Env.baseSettings),
      targets: [
        .target(
          name: Env.appName,
          destinations: Env.destinations,
          product: .app,
          bundleId: Env.bundleIdPrefix,
          deploymentTargets: Env.deploymentTargets,
          infoPlist: .extendingDefault(with: infoPlist.merging(["UILaunchScreen": [:]]) { $1 }),
          sources: ["Sources/**"],
          resources: ["Resources/**"],
          dependencies: dependencies
        ),
      ]
    )
  }

  /// Client 모듈: Interface(프로토콜·값 타입) / Impl(Apple 프레임워크 구현) / Testing(Fake) / Tests.
  /// - Parameters:
  ///   - shared: Client 가 사용하는 Shared 모듈. 네 타깃 모두에 연결된다.
  static func client(
    _ client: Client,
    shared: [Shared] = [],
    interfaceDependencies: [TargetDependency] = [],
    implDependencies: [TargetDependency] = []
  ) -> Project {
    let shared = shared.map { TargetDependency.shared($0) }
    return Project(
      name: client.rawValue,
      settings: .settings(base: Env.baseSettings),
      targets: [
        .module(name: client.interface, sources: "Interface", dependencies: shared + interfaceDependencies),
        .module(
          name: client.impl,
          sources: "Impl",
          dependencies: [.target(name: client.interface)] + shared + implDependencies
        ),
        .module(
          name: client.testing,
          sources: "Testing",
          dependencies: [.target(name: client.interface)] + shared
        ),
        .tests(
          name: client.tests,
          dependencies: [.target(name: client.impl), .target(name: client.testing)] + shared
        ),
      ]
    )
  }

  /// Feature 모듈: Feature(Model + View) / Tests / Example(Fake 로 단독 실행되는 데모 앱).
  /// - Parameters:
  ///   - clients: Feature 가 사용하는 Client. Feature 에는 Interface 가, Tests·Example 에는 Testing 이 연결된다.
  ///   - shared: Feature 가 사용하는 Shared 모듈. Feature·Tests·Example 모두에 연결된다.
  static func feature(
    _ feature: Feature,
    clients: [Client] = [],
    shared: [Shared] = []
  ) -> Project {
    let testing = clients.map { TargetDependency.client(testing: $0) }
    let shared = shared.map { TargetDependency.shared($0) }
    return Project(
      name: feature.name,
      settings: .settings(base: Env.baseSettings),
      targets: [
        .module(
          name: feature.name,
          sources: "Sources",
          dependencies: clients.map { .client(interface: $0) } + shared
        ),
        .tests(name: feature.tests, dependencies: [.target(name: feature.name)] + testing + shared),
        .target(
          name: feature.example,
          destinations: Env.destinations,
          product: .app,
          bundleId: Env.bundleId(feature.example),
          deploymentTargets: Env.deploymentTargets,
          infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
          sources: ["Example/**"],
          dependencies: [.target(name: feature.name)] + testing + shared
        ),
      ]
    )
  }

  /// Shared 모듈: 모듈 / Tests. 다른 모듈에 의존하지 않는다.
  static func shared(_ shared: Shared) -> Project {
    Project(
      name: shared.name,
      settings: .settings(base: Env.baseSettings),
      targets: [
        .module(name: shared.name, sources: "Sources", dependencies: []),
        .tests(name: shared.tests, dependencies: [.target(name: shared.name)]),
      ]
    )
  }
}

extension Target {
  static func module(name: String, sources: String, dependencies: [TargetDependency]) -> Target {
    .target(
      name: name,
      destinations: Env.destinations,
      product: .staticFramework,
      bundleId: Env.bundleId(name),
      deploymentTargets: Env.deploymentTargets,
      sources: ["\(sources)/**"],
      dependencies: dependencies
    )
  }

  static func tests(name: String, dependencies: [TargetDependency]) -> Target {
    .target(
      name: name,
      destinations: Env.destinations,
      product: .unitTests,
      bundleId: Env.bundleId(name),
      deploymentTargets: Env.deploymentTargets,
      sources: ["Tests/**"],
      dependencies: dependencies
    )
  }
}
