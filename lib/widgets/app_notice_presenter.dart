/// 应用级通知的唯一 UI 宿主。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../router/app_router.dart';
import '../services/app_notice.dart';

class AppNoticePresenter extends StatefulWidget {
  const AppNoticePresenter({super.key, required this.child, this.bus});

  final Widget child;
  final AppNoticeBus? bus;

  @override
  State<AppNoticePresenter> createState() => _AppNoticePresenterState();
}

class _AppNoticePresenterState extends State<AppNoticePresenter> {
  StreamSubscription<AppNotice>? _subscription;
  final Set<String> _presentingKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _subscription = (widget.bus ?? appNoticeBus).notices.listen(_schedule);
  }

  void _schedule(AppNotice notice) {
    if (!_presentingKeys.add(notice.dedupeKey)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _present(notice));
  }

  Future<void> _present(AppNotice notice) async {
    if (!mounted) return;
    // MaterialApp.router.builder 的 context 位于 Navigator 之上，不能直接
    // 用于 showDialog；根 overlay 的 context 才是 Navigator 的后代。
    final dialogContext = rootNavigatorKey.currentState?.overlay?.context;
    if (dialogContext == null) return;
    final l10n = AppLocalizations.of(dialogContext);
    if (l10n == null) return;
    try {
      await showDialog<void>(
        context: dialogContext,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: Text(_title(l10n, notice)),
          content: Text(_message(l10n, notice)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
    } finally {
      _presentingKeys.remove(notice.dedupeKey);
    }
  }

  String _title(AppLocalizations l10n, AppNotice notice) =>
      switch (notice.message) {
        AppNoticeMessage.playbackFailed => l10n.playbackFailedTitle,
      };

  String _message(AppLocalizations l10n, AppNotice notice) =>
      switch (notice.message) {
        AppNoticeMessage.playbackFailed => l10n.playbackFailedMessage,
      };

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
