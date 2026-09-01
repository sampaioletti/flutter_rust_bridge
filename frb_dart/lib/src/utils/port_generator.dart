import 'dart:math';

import 'package:meta/meta.dart';

/// A short random tag unique to this Dart isolate group (i.e. this browser tab, on web) — computed
/// once per load and mixed into every name these generators produce.
///
/// On web, `broadcastPort` (`_web.dart`) backs a generated port with a real `BroadcastChannel`, which
/// the browser scopes to the **origin**, not the tab or the isolate. Without this tag, both
/// generators below produced a name derived only from a bare, isolate-local counter starting at 0 on
/// every fresh load — so two tabs of the same app deterministically produced the *same* channel name
/// for corresponding ports/streams, joined the same `BroadcastChannel`, and each received the other's
/// raw wasm-pointer traffic (including `DartOpaque` handles), crashing when it tried to decode a
/// pointer meaningless in its own linear memory. On native, `broadcastPort` is a real `ReceivePort`
/// whose name is a debug label only (routing is by object identity, not by this string), so the tag
/// is harmless there — added once, here, rather than special-cased per platform.
String _newInstanceTag() {
  // `Random.nextInt`'s documented contract allows `max` up to and including 2**32, but passing
  // exactly `1 << 32` throws on web (`RangeError: max must be in range 0 < max <= 2^32, was 0`) —
  // confirmed live on stage, both mobile and desktop Chromium, immediately on every page load, since
  // `_newInstanceTag` runs the first time any port/stream name is generated during bootstrap. The
  // Dart VM (native, and the isolate-based test in `port_generator_test.dart`) evaluates the same
  // call correctly, which is why this shipped without being caught locally — only a real web build
  // exercises the dart2js-compiled path where the exact `2**32` boundary is mishandled. `0x7FFFFFFF`
  // (2**31 - 1) stays unambiguously inside every platform's native/JS-safe integer range, at the cost
  // of 1 bit of entropy per call — irrelevant for this tag's purpose (avoiding a name collision
  // between two tabs, not cryptographic security).
  final rand = Random();
  final high = rand.nextInt(0x7FFFFFFF);
  final low = rand.nextInt(0x7FFFFFFF);
  return '${high.toRadixString(16)}${low.toRadixString(16)}';
}

/// {@macro flutter_rust_bridge.internal}
@internal
class ExecuteStreamPortGenerator {
  static final _instanceTag = _newInstanceTag();
  static final _streamSinkNameIndex = <String, int>{};

  /// {@macro flutter_rust_bridge.internal}
  static String create(String funcName) {
    final nextIndex = _streamSinkNameIndex.update(
      funcName,
      (value) => value + 1,
      ifAbsent: () => 0,
    );
    return '__frb_streamsink_${_instanceTag}_${funcName}_$nextIndex';
  }
}

/// {@macro flutter_rust_bridge.internal}
@internal
class BaseLazyPortIdGenerator {
  static final _instanceTag = _newInstanceTag();
  static int _nextPort = 0;

  /// {@macro flutter_rust_bridge.internal}
  static String create() => '__frb_lazy_port_${_instanceTag}_${_nextPort++}';
}
