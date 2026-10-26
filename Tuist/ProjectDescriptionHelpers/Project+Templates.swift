import ProjectDescription

public enum Env {
  public static let appName = "SnapSort"
  public static let bundleIdPrefix = "com.zopandagom.snapsort"
  public static let destinations: Destinations = [.iPhone]
  /// Foundation Models 가 동작하는 최소 버전.
  public static let deploymentTargets: DeploymentTargets = .iOS("26.0")
  /// Apple Developer Program 팀. 실기기 빌드는 Xcode 자동 서명으로 프로비저닝한다.
  static let developmentTeam = "XHV4ZL5K8T"

  static let baseSettings: SettingsDictionary = [
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "CODE_SIGN_STYLE": "Automatic",
    "DEVELOPMENT_TEAM": .string(Self.developmentTeam),
  ]

  /// 앱과 위젯이 저장소를 함께 쓰는 App Group. 이름의 단일 출처이며, Swift 코드는 Info.plist 의
  /// `appGroupInfoKey` 로 읽는다 (docs/ARCHITECTURE.md §4 저장소).
  public static let appGroupIdentifier = "group.com.zopandagom.snapsort"
  public static let appGroupInfoKey = "SnapSortAppGroupIdentifier"

  /// 서명 없는 빌드(`CODE_SIGNING_ALLOWED=NO`)에는 들어가지 않아 group 컨테이너가 nil 이다. 그때 앱은 옛 위치를 쓴다.
  static let appGroupEntitlements: Entitlements = .dictionary([
    "com.apple.security.application-groups": .array([.string(Self.appGroupIdentifier)]),
  ])

  static func bundleId(_ name: String) -> String {
    "\(self.bundleIdPrefix).\(name.lowercased())"
  }
}

public extension Project {
  /// 앱 조립 지점. Feature 와 Client Impl 을 모두 알고 있는 두 조립 지점(App·Extension) 중 앱.
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
          infoPlist: .extendingDefault(with: infoPlist.merging([
            "UILaunchScreen": [:],
            Env.appGroupInfoKey: .string(Env.appGroupIdentifier),
          ]) { $1 }),
          buildableFolders: ["Sources", "Resources"],
          entitlements: Env.appGroupEntitlements,
          dependencies: dependencies
        ),
      ]
    )
  }

  /// 앱 확장 조립 지점(위젯 등). Feature 와 Client Impl 을 조립하며, App 이 의존해 임베드한다.
  /// 타깃은 하나(`SnapSort<Name>`)이고 App 과 같은 App Group 을 쓴다.
  static func appExtension(_ appExtension: AppExtension, dependencies: [TargetDependency]) -> Project {
    Project(
      name: appExtension.rawValue,
      options: .options(defaultKnownRegions: ["ko", "en"], developmentRegion: "ko"),
      settings: .settings(base: Env.baseSettings),
      targets: [
        .target(
          name: appExtension.name,
          destinations: Env.destinations,
          product: .appExtension,
          bundleId: Env.bundleId(appExtension.rawValue),
          deploymentTargets: Env.deploymentTargets,
          infoPlist: .extendingDefault(with: [
            "CFBundleDisplayName": .string(Env.appName),
            "NSExtension": [
              "NSExtensionPointIdentifier": "com.apple.widgetkit-extension",
            ],
            Env.appGroupInfoKey: .string(Env.appGroupIdentifier),
          ]),
          buildableFolders: ["Sources"],
          entitlements: Env.appGroupEntitlements,
          dependencies: dependencies
        ),
      ]
    )
  }

  /// Client 모듈: Interface(프로토콜·값 타입) / Impl(Apple 프레임워크 구현 또는 다른 Client 조합) / Testing(Fake) / Tests.
  /// - Parameters:
  ///   - shared: Client 가 사용하는 Shared 모듈. 네 타깃 모두에 연결된다.
  ///   - clients: Impl 이 조합하는 다른 Client (예: Indexing 이 쓰는 PhotoLibrary·ImageAnalysis·PhotoStore·Classifier).
  ///     Impl 에는 Interface 가, Tests 에는 Interface 와 Fake 가 든 Testing 이 연결된다.
  static func client(
    _ client: Client,
    shared: [Shared] = [],
    clients: [Client] = [],
    interfaceDependencies: [TargetDependency] = [],
    implDependencies: [TargetDependency] = []
  ) -> Project {
    let shared = shared.map { TargetDependency.shared($0) }
    let otherInterfaces = clients.map { TargetDependency.client(interface: $0) }
    let otherTestings = clients.map { TargetDependency.client(testing: $0) }
    return Project(
      name: client.rawValue,
      settings: .settings(base: Env.baseSettings),
      targets: [
        .module(name: client.interface, sources: "Interface", dependencies: shared + interfaceDependencies),
        .module(
          name: client.impl,
          sources: "Impl",
          dependencies: [.target(name: client.interface)] + shared + otherInterfaces + implDependencies
        ),
        .module(
          name: client.testing,
          sources: "Testing",
          dependencies: [.target(name: client.interface)] + shared
        ),
        .tests(
          name: client.tests,
          dependencies: [.target(name: client.impl), .target(name: client.testing)] + shared + otherInterfaces
            + otherTestings
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
          buildableFolders: ["Example"],
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
      buildableFolders: [.folder(.relativeToManifest(sources))],
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
      buildableFolders: ["Tests"],
      dependencies: dependencies
    )
  }
}
