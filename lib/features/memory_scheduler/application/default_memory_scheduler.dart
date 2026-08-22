/// 默认记忆调度 facade：编排 Registry、算法 adapter 与 Repository。
library;

import 'package:clock/clock.dart';

import 'memory_model_registry.dart';
import 'memory_profile_registry.dart';
import 'memory_schedule_repository.dart';
import 'memory_scheduler.dart';
import '../domain/memory_model_adapter.dart';
import '../domain/memory_profile.dart';
import '../domain/memory_rating.dart';
import '../domain/memory_schedule.dart';
import '../domain/memory_scheduler_commands.dart';
import '../domain/memory_scheduler_exceptions.dart';
import '../domain/memory_scheduler_results.dart';
import '../domain/memory_subject_ref.dart';

/// 默认 facade 的纯业务编排实现。
final class DefaultMemoryScheduler implements MemoryScheduler {
  /// 注入所有副作用边界；算法计算本身保持同步且可复现。
  DefaultMemoryScheduler({
    required MemoryScheduleRepository repository,
    required MemoryProfileRegistry profileRegistry,
    required MemoryModelRegistry modelRegistry,
    required MemoryIdGenerator idGenerator,
    required Clock clock,
  }) : _repository = repository,
       _profileRegistry = profileRegistry,
       _modelRegistry = modelRegistry,
       _idGenerator = idGenerator,
       _clock = clock;

  final MemoryScheduleRepository _repository;
  final MemoryProfileRegistry _profileRegistry;
  final MemoryModelRegistry _modelRegistry;
  final MemoryIdGenerator _idGenerator;
  final Clock _clock;

  @override
  Future<MemorySchedule> ensureSchedule(
    EnsureMemoryScheduleCommand command,
  ) async {
    final profileRef =
        command.profile ??
        _profileRegistry.defaultForNamespace(command.subject.namespace);
    final profile = _profileRegistry.get(profileRef);
    final adapter = _adapterFor(profile);
    final state = adapter.createInitialState(
      profile: profile,
      createdAt: command.occurredAt,
    );
    final created = MemorySchedule(
      id: _idGenerator.newId(),
      subject: command.subject,
      profile: profile.ref,
      modelId: adapter.modelId,
      modelStateVersion: state.version,
      phase: MemorySchedulePhase.newItem,
      status: MemoryScheduleStatus.active,
      createdAt: command.occurredAt,
      updatedAt: command.occurredAt,
      lastReviewedAt: null,
      dueAt: command.occurredAt,
      reviewCount: 0,
      lapseCount: 0,
      revision: 0,
      modelState: state.values,
      archivedAt: null,
    );
    final result = await _repository.createIfAbsent(created);
    if (result.status == MemoryScheduleStatus.archived) {
      throw const MemoryScheduleArchivedException('调度已归档，必须显式恢复。');
    }
    return result;
  }

  @override
  Future<MemorySchedule?> getSchedule(MemorySubjectRef subject) =>
      _repository.getBySubject(subject);

  @override
  Future<List<MemorySchedule>> getSchedules(Set<MemorySubjectRef> subjects) =>
      _repository.getBySubjects(subjects);

  @override
  Stream<MemorySchedule?> watchSchedule(MemorySubjectRef subject) =>
      _repository.watchBySubject(subject);

  @override
  Future<List<MemorySchedule>> getDueSchedules(DueMemorySchedulesQuery query) =>
      _repository.getDue(query);

  @override
  Future<int> getDueCount(DueMemoryCountQuery query) =>
      _repository.getDueCount(query);

  @override
  Stream<int> watchDueCount(DueMemoryCountQuery query) =>
      _repository.watchDueCount(query);

  @override
  double retrievability(MemorySchedule schedule, DateTime at) {
    final profile = _profileRegistry.get(schedule.profile);
    final adapter = _adapterFor(profile);
    return adapter.retrievability(
      profile: profile,
      current: _stateFor(schedule, adapter),
      at: at.toUtc(),
    );
  }

  @override
  Future<MemoryRatingPreviewSet> previewRatings(
    PreviewMemoryRatingsQuery query,
  ) async {
    final schedule = await _activeSchedule(query.subject);
    _checkExpectedRevision(schedule, query.expectedRevision);
    _checkReviewTime(schedule, query.reviewedAt);
    final profile = _profileRegistry.get(schedule.profile);
    final adapter = _adapterFor(profile);
    final previews = adapter.preview(
      profile: profile,
      current: _stateFor(schedule, adapter),
      reviewedAt: query.reviewedAt,
    );
    return MemoryRatingPreviewSet(
      scheduleId: schedule.id,
      revision: schedule.revision,
      reviewedAt: query.reviewedAt,
      again: _toPreview(
        schedule,
        MemoryRating.again,
        previews.again,
        query.reviewedAt,
      ),
      hard: _toPreview(
        schedule,
        MemoryRating.hard,
        previews.hard,
        query.reviewedAt,
      ),
      good: _toPreview(
        schedule,
        MemoryRating.good,
        previews.good,
        query.reviewedAt,
      ),
      easy: _toPreview(
        schedule,
        MemoryRating.easy,
        previews.easy,
        query.reviewedAt,
      ),
    );
  }

  @override
  Future<MemoryReviewResult> review(ReviewMemoryCommand command) async {
    final before = await _activeSchedule(command.subject);
    final preview = command.preview;
    if (preview != null) {
      _checkExpectedRevision(before, command.expectedRevision);
      if (preview.rating != command.rating ||
          preview.scheduleId != before.id ||
          preview.revision != before.revision ||
          preview.reviewedAt != command.reviewedAt) {
        throw const MemoryScheduleConflictException('评分预览已过期。');
      }
      _checkReviewTime(before, command.reviewedAt);
    }
    final transition = preview?.transition ?? _transitionFor(before, command);
    final isLapse =
        before.phase == MemorySchedulePhase.review &&
        command.rating == MemoryRating.again;
    final after = MemorySchedule(
      id: before.id,
      subject: before.subject,
      profile: before.profile,
      modelId: before.modelId,
      modelStateVersion: transition.state.version,
      phase: transition.phase,
      status: MemoryScheduleStatus.active,
      createdAt: before.createdAt,
      updatedAt: command.reviewedAt,
      lastReviewedAt: transition.lastReviewedAt,
      dueAt: transition.dueAt,
      reviewCount: before.reviewCount + 1,
      lapseCount: before.lapseCount + (isLapse ? 1 : 0),
      revision: before.revision + 1,
      modelState: transition.state.values,
      archivedAt: null,
    );
    return _repository.commitReview(
      MemoryReviewCommit(
        before: before,
        after: after,
        event: MemoryReviewEventDraft(
          id: _idGenerator.newId(),
          operationId: command.operationId,
          rating: command.rating,
          isLapse: isLapse,
          reviewedAt: command.reviewedAt,
          responseTime: command.responseTime,
          dueBefore: before.dueAt,
          createdAt: _clock.now().toUtc(),
        ),
        expectedRevision: command.expectedRevision,
      ),
    );
  }

  @override
  Future<MemorySchedule> archive(ArchiveMemoryScheduleCommand command) async {
    final before = await _activeSchedule(command.subject);
    _checkExpectedRevision(before, command.expectedRevision);
    return _repository.replaceLifecycle(
      before,
      _lifecycleCopy(
        before,
        status: MemoryScheduleStatus.archived,
        at: command.archivedAt,
      ),
    );
  }

  @override
  Future<MemorySchedule> restore(RestoreMemoryScheduleCommand command) async {
    final before = await _scheduleOrThrow(command.subject);
    if (before.status != MemoryScheduleStatus.archived) {
      throw const MemoryScheduleStatusException('只有归档调度可以恢复。');
    }
    _checkExpectedRevision(before, command.expectedRevision);
    return _repository.replaceLifecycle(
      before,
      _lifecycleCopy(
        before,
        status: MemoryScheduleStatus.active,
        at: command.restoredAt,
      ),
    );
  }

  @override
  Future<void> purge(PurgeMemoryScheduleCommand command) async {
    final schedule = await _scheduleOrThrow(command.subject);
    _checkExpectedRevision(schedule, command.expectedRevision);
    await _repository.purge(schedule);
  }

  MemoryModelAdapter _adapterFor(MemoryProfile profile) {
    final adapter = _modelRegistry.get(profile.modelId);
    adapter.validateProfile(profile);
    return adapter;
  }

  MemoryModelTransition _transitionFor(
    MemorySchedule before,
    ReviewMemoryCommand command,
  ) {
    final profile = _profileRegistry.get(before.profile);
    final adapter = _adapterFor(profile);
    return adapter.review(
      profile: profile,
      current: _stateFor(before, adapter),
      rating: command.rating,
      reviewedAt: command.reviewedAt,
    );
  }

  MemoryModelState _stateFor(
    MemorySchedule schedule,
    MemoryModelAdapter adapter,
  ) {
    if (!adapter.supportedStateVersions.contains(schedule.modelStateVersion)) {
      throw MemoryModelStateUnsupportedException(
        '模型 ${schedule.modelId} 不支持状态版本 ${schedule.modelStateVersion}。',
      );
    }
    return MemoryModelState(
      version: schedule.modelStateVersion,
      values: schedule.modelState,
    );
  }

  Future<MemorySchedule> _scheduleOrThrow(MemorySubjectRef subject) async {
    final schedule = await _repository.getBySubject(subject);
    if (schedule == null) {
      throw const MemoryScheduleNotFoundException('调度不存在。');
    }
    return schedule;
  }

  Future<MemorySchedule> _activeSchedule(MemorySubjectRef subject) async {
    final schedule = await _scheduleOrThrow(subject);
    if (schedule.status != MemoryScheduleStatus.active) {
      throw const MemoryScheduleArchivedException('归档调度不能执行此操作。');
    }
    return schedule;
  }

  void _checkExpectedRevision(MemorySchedule schedule, int? expectedRevision) {
    if (expectedRevision != null && schedule.revision != expectedRevision) {
      throw const MemoryScheduleConflictException('调度 revision 已过期。');
    }
  }

  void _checkReviewTime(MemorySchedule schedule, DateTime reviewedAt) {
    final lastReviewedAt = schedule.lastReviewedAt;
    if (lastReviewedAt != null && reviewedAt.isBefore(lastReviewedAt)) {
      throw const MemoryReviewTimeOrderException('评分时间不能早于上一次评分。');
    }
  }

  MemoryRatingPreview _toPreview(
    MemorySchedule schedule,
    MemoryRating rating,
    MemoryModelPreview preview,
    DateTime reviewedAt,
  ) => MemoryRatingPreview(
    scheduleId: schedule.id,
    revision: schedule.revision,
    rating: rating,
    reviewedAt: reviewedAt,
    dueAt: preview.dueAt,
    interval: preview.dueAt.difference(reviewedAt.toUtc()),
    phase: preview.phase,
    transition: MemoryModelTransition(
      state: preview.state,
      phase: preview.phase,
      dueAt: preview.dueAt,
      lastReviewedAt: preview.lastReviewedAt,
    ),
  );

  MemorySchedule _lifecycleCopy(
    MemorySchedule before, {
    required MemoryScheduleStatus status,
    required DateTime at,
  }) => MemorySchedule(
    id: before.id,
    subject: before.subject,
    profile: before.profile,
    modelId: before.modelId,
    modelStateVersion: before.modelStateVersion,
    phase: before.phase,
    status: status,
    createdAt: before.createdAt,
    updatedAt: at,
    lastReviewedAt: before.lastReviewedAt,
    dueAt: before.dueAt,
    reviewCount: before.reviewCount,
    lapseCount: before.lapseCount,
    revision: before.revision + 1,
    modelState: before.modelState,
    archivedAt: status == MemoryScheduleStatus.archived ? at : null,
  );
}
