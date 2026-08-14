/// 不读取业务状态的 Flashcard 页面骨架。
library;

import 'package:flutter/material.dart';

/// 负责布局，不负责卡片内容和流程编排。
class ScheduledFlashcardScaffold extends StatelessWidget {
  const ScheduledFlashcardScaffold({
    super.key,
    required this.title,
    required this.position,
    required this.total,
    required this.content,
    required this.footer,
    this.onClose,
    this.actions = const <Widget>[],
  });

  final String title;
  final int position;
  final int total;
  final Widget content;
  final Widget footer;
  final VoidCallback? onClose;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : position.clamp(0, total) / total;
    return Scaffold(
      appBar: AppBar(
        leading: onClose == null
            ? null
            : IconButton(
                tooltip: 'Close',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
        title: Text(title),
        actions: actions,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text('$position / $total'),
                const SizedBox(width: 12),
                Expanded(child: LinearProgressIndicator(value: progress)),
              ],
            ),
          ),
          Expanded(child: content),
          SafeArea(
            top: false,
            maintainBottomViewPadding: true,
            child: Padding(padding: const EdgeInsets.all(16), child: footer),
          ),
        ],
      ),
    );
  }
}
