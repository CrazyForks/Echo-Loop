import 'package:echo_loop/services/media_kit_debug_initializer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('热重启旧引用先清 wakeup callback 再发送 quit', () {
    final calls = <String>[];
    final testCleaner = MediaKitHotRestartReferenceCleaner(
      clearWakeupCallback: (address) => calls.add('clear:$address'),
      quit: (address) => calls.add('quit:$address'),
    );

    testCleaner.clean([11, 22]);

    expect(calls, ['clear:11', 'clear:22', 'quit:11', 'quit:22']);
  });
}
