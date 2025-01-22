import 'package:frb_example_dart_minimal/src/rust/api/minimal.dart';
import 'package:frb_example_dart_minimal/src/rust/frb_generated.dart';

import 'src/rust/api/minimal.dart';

// If you are developing a binary program, you may want to put it in `bin/something.dart`
Future<void> main() async {
  await RustLib.init();
  print('Call Rust and get: 100+200 = ${await minimalAdder(a: 100, b: 200)}');

  await sleepFn(sleepCb: (ms) async {
    print("sleeping $ms");
    await Future.delayed(Duration(milliseconds: ms));
    print("returinging $ms");
  });

  await Future.delayed(Duration(milliseconds: 5000));
}
