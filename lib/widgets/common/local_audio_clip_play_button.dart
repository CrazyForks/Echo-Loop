import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/short_audio_player_provider.dart';
import '../../services/pronunciation/local_audio_clip_player.dart';

/// 可复用的本地短音频播放按钮。
///
/// 组件自身管理加载、播放和停止三种 UI 状态；多个按钮共享播放器时，
/// 只有 [playbackKey] 匹配当前播放任务的按钮会显示播放中。
class LocalAudioClipPlayButton extends ConsumerStatefulWidget {
  const LocalAudioClipPlayButton({
    super.key,
    required this.filePath,
    this.player,
    this.playbackKey,
    this.playIcon = Icons.play_arrow_rounded,
    this.stopIcon = Icons.stop_rounded,
    this.showStopButton = true,
    this.start,
    this.end,
    this.tooltip,
    this.iconSize,
    this.padding,
    this.constraints,
    this.visualDensity,
  }) : assert(
         (start == null) == (end == null),
         'start and end must be provided together',
       );

  final String filePath;
  final LocalAudioClipPlayer? player;
  final String? playbackKey;
  final IconData playIcon;
  final IconData stopIcon;
  final bool showStopButton;
  final Duration? start;
  final Duration? end;
  final String? tooltip;
  final double? iconSize;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;
  final VisualDensity? visualDensity;

  @override
  ConsumerState<LocalAudioClipPlayButton> createState() =>
      _LocalAudioClipPlayButtonState();
}

class _LocalAudioClipPlayButtonState
    extends ConsumerState<LocalAudioClipPlayButton> {
  StreamSubscription<LocalAudioClipPlaybackState>? _subscription;
  LocalAudioClipPlayer? _player;
  bool _loading = false;
  int _requestId = 0;

  String get _key => widget.playbackKey ?? widget.filePath;

  @override
  void initState() {
    super.initState();
    _attach(widget.player);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attach(widget.player ?? ref.read(shortAudioPlayerProvider));
  }

  @override
  void didUpdateWidget(covariant LocalAudioClipPlayButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.player, widget.player)) {
      _attach(widget.player ?? ref.read(shortAudioPlayerProvider));
    }
  }

  void _attach(LocalAudioClipPlayer? player) {
    if (player == null || identical(player, _player)) return;
    unawaited(_subscription?.cancel());
    _player = player;
    _subscription = player.states.listen((state) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    });
  }

  bool get _isPlaying => _player?.state.playingKey == _key;

  Future<void> _toggle() async {
    final player = _player;
    if (player == null) return;
    if (_isPlaying) {
      await player.stop();
      return;
    }
    if (_loading) return;
    final requestId = ++_requestId;
    setState(() => _loading = true);
    // 让加载态至少经历一个 frame，避免同步播放器初始化直接跳过视觉反馈。
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (!mounted || requestId != _requestId) return;
    final result = widget.start != null && widget.end != null
        ? await player.playRangeFile(
            widget.filePath,
            start: widget.start!,
            end: widget.end!,
            playbackKey: _key,
          )
        : await player.playFile(widget.filePath, playbackKey: _key);
    if (!mounted || requestId != _requestId) return;
    if (result != AudioPlaybackResult.cancelled) {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _requestId++;
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final playing = _isPlaying;
    final loading = _loading && !playing;
    final stopping = playing && widget.showStopButton;
    final icon = loading
        ? SizedBox(
            width: widget.iconSize ?? 24,
            height: widget.iconSize ?? 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.primary,
            ),
          )
        : Icon(
            stopping ? widget.stopIcon : widget.playIcon,
            color: stopping ? colors.error : colors.primary,
            size: widget.iconSize,
          );
    return IconButton(
      tooltip: widget.tooltip,
      onPressed:
          widget.filePath.trim().isEmpty ||
              loading ||
              (playing && !widget.showStopButton)
          ? null
          : _toggle,
      icon: icon,
      padding: widget.padding,
      constraints: widget.constraints,
      visualDensity: widget.visualDensity,
    );
  }
}
