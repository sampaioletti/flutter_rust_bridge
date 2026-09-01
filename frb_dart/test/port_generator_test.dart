// Regression coverage for a cross-tab collision bug: on web, `broadcastPort` (see
// `src/generalized_isolate/_web.dart`) backs a generated port with a real `BroadcastChannel`, which
// the browser scopes to the *origin*, not the isolate/tab. Before the fix in `port_generator.dart`,
// both generators below derived a name from nothing but a bare, isolate-local counter starting at 0
// on every fresh load — so two browser tabs of the same app deterministically produced the *same*
// channel name, joined the same `BroadcastChannel`, and each received the other's raw wasm-pointer
// traffic. `Isolate.spawn` gives each child isolate genuinely separate static state (its own heap, no
// shared statics with the parent or with a sibling), which is the same "fresh realm" property that
// makes two browser tabs independent — so spawning two isolates and comparing what they each generate
// is a faithful, native-testable proxy for "two tabs," even though the actual bug only manifests on
// web (where the name is a real routing key, not just a debug label).
import 'dart:isolate';

import 'package:flutter_rust_bridge/src/utils/port_generator.dart';
import 'package:test/test.dart';

void main() {
  group('BaseLazyPortIdGenerator', () {
    test('produces unique, incrementing names within one isolate', () {
      final a = BaseLazyPortIdGenerator.create();
      final b = BaseLazyPortIdGenerator.create();
      expect(a, isNot(equals(b)));
      expect(a, startsWith('__frb_lazy_port_'));
    });

    test('two independent isolates never produce the same name', () async {
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
    });
  });

  group('ExecuteStreamPortGenerator', () {
    test(
      'two independent isolates never produce the same name for the same function',
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
