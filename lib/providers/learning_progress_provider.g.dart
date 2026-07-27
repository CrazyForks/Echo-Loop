// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'learning_progress_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$learningProgressNotifierHash() =>
    r'1990e3b32cc3fadabfcb0bb40e80408ad46be115';

/// 学习进度管理 Provider
///
/// 管理所有音频的学习进度，提供加载、创建、推进、设置难度等操作。
/// 推进子步骤时同时写入 stage_completions 历史记录。
///
/// Copied from [LearningProgressNotifier].
@ProviderFor(LearningProgressNotifier)
final learningProgressNotifierProvider =
    NotifierProvider<LearningProgressNotifier, LearningProgressState>.internal(
      LearningProgressNotifier.new,
      name: r'learningProgressNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$learningProgressNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$LearningProgressNotifier = Notifier<LearningProgressState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
