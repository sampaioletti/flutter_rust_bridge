// Regression coverage for two bugs found back-to-back in the same fix:
//
// 1. A cross-tab collision: on web, `broadcastPort` (see `src/generalized_isolate/_web.dart`) backs a
//    generated port with a real `BroadcastChannel`, which the browser scopes to the *origin*, not the
//    isolate/tab. Before the fix in `port_generator.dart`, both generators below derived a name from
//    nothing but a bare, isolate-local counter starting at 0 on every fresh load — so two browser tabs
//    of the same app deterministically produced the *same* channel name, joined the same
//    `BroadcastChannel`, and each received the other's raw wasm-pointer traffic.
// 2. The FIRST fix for (1) used `Random().nextInt(1 << 32)` to build the per-tab tag. `1 << 32` is a
//    valid `int` on the Dart VM (where these isolate-based tests run) — but dart2js's compiled
//    `Random.nextInt` mishandles that exact boundary value and throws `RangeError: max must be in
//    range 0 < max <= 2^32, was 0` on every single page load, on every browser — reported live as
//    "the app doesn't open," reproduced identically on desktop and mobile. The VM-only tests below
//    passed the whole time; nothing here ran under a JS-compiled platform until this was chased down
//    with `dart compile js` + Node. The plain, non-isolate test right below this comment is the one
//    that must run under `dart test -p node` or `-p chrome` (not just the default VM platform) to
//    actually exercise dart2js and catch a regression like this again.
import 'dart:isolate';

import 'package:flutter_rust_bridge/src/utils/port_generator.dart';
import 'package:test/test.dart';

void main() {
  group('BaseLazyPortIdGenerator', () {
    test(
      'produces unique, incrementing names without throwing (run this under '
      '-p node/-p chrome, not just the default vm platform — see the file header)',
      () {
        final a = BaseLazyPortIdGenerator.create();
        final b = BaseLazyPortIdGenerator.create();
        expect(a, isNot(equals(b)));
        expect(a, startsWith('__frb_lazy_port_'));
      },
    );

    // Isolate.spawn is VM-only (dart2js/dart2wasm have no working `ReceivePort.sendPort` for a
    // spawned isolate) — this proves cross-*realm* uniqueness (the isolate boundary is a faithful
    // proxy for "two tabs," per the file header), not the web-specific numeric bug above.
    test(
      'two independent isolates never produce the same name',
      testOn: 'vm',
      () async {
        final first = await _createInChildIsolate(_isolateEntryBaseLazyPort);
        final second = await _createInChildIsolate(_isolateEntryBaseLazyPort);
        expect(
          first,
          isNot(equals(second)),
          reason:
              'a bare, isolate-local counter starting at 0 in every fresh isolate used to produce '
              'the exact same name for two "tabs" — this asserts the per-realm random tag prevents '
              'that collision',
        );
      },
    );
  });

  group('ExecuteStreamPortGenerator', () {
    test(
      'two independent isolates never produce the same name for the same function',
      testOn: 'vm',
      () async {
        final first = await _createInChildIsolate(
          _isolateEntryExecuteStreamPort,
        );
        final second = await _createInChildIsolate(
          _isolateEntryExecuteStreamPort,
        );
        expect(first, isNot(equals(second)));
      },
    );
  });
}

Future<String> _createInChildIsolate(void Function(SendPort) entry) async {
  final receivePort = ReceivePort();
  await Isolate.spawn(entry, receivePort.sendPort);
  final result = await receivePort.first;
  receivePort.close();
  return result as String;
}

void _isolateEntryBaseLazyPort(SendPort sendPort) {
  sendPort.send(BaseLazyPortIdGenerator.create());
}

void _isolateEntryExecuteStreamPort(SendPort sendPort) {
  sendPort.send(ExecuteStreamPortGenerator.create('sameFuncName'));
}
