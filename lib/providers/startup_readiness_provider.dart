import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 冷启动中本地数据是否已经可安全读取。
///
/// `runApp` 后数据库迁移和内置示例安装仍会继续执行。主导航树必须等待该
/// 状态变为 [StartupLocalDataStatus.ready]，否则默认学习页会抢先打开数据库。
enum StartupLocalDataStatus { preparing, ready, failed }

/// 启动 gate 的最小状态，仅协调启动顺序，不承载业务数据。
class StartupReadiness {
  const StartupReadiness({
    this.localDataStatus = StartupLocalDataStatus.preparing,
  });

  final StartupLocalDataStatus localDataStatus;

  bool get isLocalDataReady => localDataStatus == StartupLocalDataStatus.ready;

  StartupReadiness copyWith({StartupLocalDataStatus? localDataStatus}) {
    return StartupReadiness(
      localDataStatus: localDataStatus ?? this.localDataStatus,
    );
  }
}

/// 由应用启动编排器写入、由主导航壳读取的本地数据就绪状态。
final startupReadinessProvider =
    NotifierProvider<StartupReadinessNotifier, StartupReadiness>(
      StartupReadinessNotifier.new,
    );

class StartupReadinessNotifier extends Notifier<StartupReadiness> {
  @override
  StartupReadiness build() => const StartupReadiness();

  /// 数据库迁移与必要的本地首启数据已完成，可创建业务页面。
  void markLocalDataReady() {
    state = state.copyWith(localDataStatus: StartupLocalDataStatus.ready);
  }

  /// 本地启动任务失败时保留 gate，避免半迁移数据被业务页面读取。
  void markLocalDataFailed() {
    state = state.copyWith(localDataStatus: StartupLocalDataStatus.failed);
  }
}
