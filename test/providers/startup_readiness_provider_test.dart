import 'package:echo_loop/providers/startup_readiness_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('本地数据完成前保持 gate，完成后才释放主导航', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(startupReadinessProvider).localDataStatus,
      StartupLocalDataStatus.preparing,
    );
    expect(container.read(startupReadinessProvider).isLocalDataReady, isFalse);

    container.read(startupReadinessProvider.notifier).markLocalDataReady();

    expect(container.read(startupReadinessProvider).isLocalDataReady, isTrue);
  });

  test('迁移失败时不释放主导航 gate', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(startupReadinessProvider.notifier).markLocalDataFailed();

    expect(
      container.read(startupReadinessProvider).localDataStatus,
      StartupLocalDataStatus.failed,
    );
    expect(container.read(startupReadinessProvider).isLocalDataReady, isFalse);
  });
}
