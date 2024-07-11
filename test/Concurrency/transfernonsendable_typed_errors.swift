// RUN: %target-swift-frontend -swift-version 6 -Xllvm -sil-regionbasedisolation-force-use-of-typed-errors -emit-sil -o /dev/null %s -verify

// REQUIRES: concurrency
// REQUIRES: asserts

// READ THIS: This test is only intended to test typed errors that are fallback
// error paths that are only invoked if we can't find a name for the value being
// sent. Since in most cases we are able to infer a name, we do not invoke these
// very often (and in truth in normal compilation we would like to never emit
// them). To make sure that we can at least test them out, this test uses an
// asserts only option that causes us to emit typed errors even when we find a
// name.

////////////////////////
// MARK: Declarations //
////////////////////////

class NonSendableKlass {}

actor MyActor {}

@MainActor func transferToMain<T>(_ t: T) async {}

/////////////////
// MARK: Tests //
/////////////////

func simpleUseAfterFree() async {
  let x = NonSendableKlass()
  await transferToMain(x) // expected-error {{sending value of non-Sendable type 'NonSendableKlass' risks causing data races}}
  // expected-note @-1 {{sending value of non-Sendable type 'NonSendableKlass' to main actor-isolated global function 'transferToMain' risks causing data races between main actor-isolated and local nonisolated uses}}
  print(x) // expected-note {{access can happen concurrently}}
}

func isolatedClosureTest() async {
  let x = NonSendableKlass()
  let _ = { @MainActor in
      print(x) // expected-error {{sending value of non-Sendable type 'NonSendableKlass' risks causing data races}}
      // expected-note @-1 {{sending value of non-Sendable type 'NonSendableKlass' to main actor-isolated closure due to closure capture risks causing races in between main actor-isolated and nonisolated uses}}
  }
  print(x) // expected-note {{access can happen concurrently}}
}

func sendingError() async {
  func test(_ x: sending NonSendableKlass) {}
  let x = NonSendableKlass()
  test(x) // expected-error {{sending value of non-Sendable type 'NonSendableKlass' risks causing data races}}
  // expected-note @-1 {{Passing value of non-Sendable type 'NonSendableKlass' as a 'sending' argument to local function 'test' risks causing races in between local and caller code}}
  print(x) // expected-note {{access can happen concurrently}}
}

extension MyActor {
  func testNonSendableCaptures(sc: NonSendableKlass) {
    Task {
      _ = self
      _ = sc

      Task { [sc,self] in
        _ = self
        _ = sc

        Task { // expected-error {{sending value of non-Sendable type '() async -> ()' risks causing data races}}
          // expected-note @-1 {{Passing value of non-Sendable type '() async -> ()' as a 'sending' argument risks causing races in between local and caller code}}
          _ = sc
        }

        Task { // expected-note {{access can happen concurrently}}
          _ = sc
        }
      }
    }
  }
}
