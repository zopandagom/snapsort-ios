import Core
import Foundation
import PhotoLibraryInterface
import PhotoLibraryTesting
import Synchronization
import Testing
@testable import LibraryFeature

/// 식별자마다 바로 읽히는 보관함 대역. `gates` 를 주면 읽기 전에 문을 지난다.
func coverLibrary(_ ids: [ImageAsset.ID], gates: LoadGates? = nil) -> PhotoLibraryClientFake {
  let loadGate: (@Sendable (ImageAsset.ID) async -> Void)? = if let gates {
    { id in await gates.pass(id) }
  } else {
    nil
  }
  return PhotoLibraryClientFake(
    loadImageResults: Dictionary(uniqueKeysWithValues: ids.map { ($0, .success(.stub())) }),
    loadGate: loadGate
  )
}

/// 로더를 시작하고 요청 통로를 열 때까지 양보한다.
@MainActor
func startLoader(_ model: LibraryCoverModel) async -> Task<Void, Never> {
  let loader = Task { await model.onAppear() }
  await settle()
  return loader
}

extension PhotoLibraryClientFake {
  /// 그 식별자의 `loadImage` 요청 수.
  func requestCount(_ id: ImageAsset.ID) -> Int {
    self.loadImageRequests.count { $0.id == id }
  }
}

/// 식별자의 몇 번째 읽기인지로 붙잡는 문. 붙잡은 읽기는 열 때까지 기다리고, Task 가 취소되면 바로 지나간다
/// (Fake 가 취소를 확인해 `.cancelled` 를 던진다). 대표 로더는 한 식별자를 한 번에 하나만 읽으므로 번호가 정해진다.
final class LoadGates: Sendable {
  struct Key: Hashable, Sendable {
    let id: ImageAsset.ID
    let call: Int

    init(_ id: ImageAsset.ID, _ call: Int) {
      self.id = id
      self.call = call
    }
  }

  private struct State {
    var held: Set<Key>
    var entered: [ImageAsset.ID: Int] = [:]
    var passed: [ImageAsset.ID: Int] = [:]
  }

  private let state: Mutex<State>

  init(holding keys: Set<Key>) {
    self.state = Mutex(State(held: keys))
  }

  func pass(_ id: ImageAsset.ID) async {
    let key = self.state.withLock { state in
      defer { state.entered[id, default: 0] += 1 }
      return Key(id, state.entered[id, default: 0])
    }
    while self.state.withLock({ $0.held.contains(key) }), !Task.isCancelled {
      try? await Task.sleep(for: .milliseconds(5))
    }
    self.state.withLock { $0.passed[id, default: 0] += 1 }
  }

  func enteredCount(_ id: ImageAsset.ID) -> Int {
    self.state.withLock { $0.entered[id, default: 0] }
  }

  func passedCount(_ id: ImageAsset.ID) -> Int {
    self.state.withLock { $0.passed[id, default: 0] }
  }

  func open(_ key: Key) {
    self.state.withLock { _ = $0.held.remove(key) }
  }

  func openAll() {
    self.state.withLock { $0.held.removeAll() }
  }
}
