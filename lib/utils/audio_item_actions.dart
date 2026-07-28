// 音频条目的共享操作。
//
// 资源库/合集列表项菜单（[AudioListTile]）与学习计划页顶栏菜单共用同一套
// 「管理字幕 / 导出音频」逻辑，避免导出等较复杂流程在两处重复。
// 编辑字幕、导出 PDF 只是单行路由跳转，仍在各调用点内联，不在此聚合。
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:universal_io/io.dart';

import '../database/providers.dart';
import '../l10n/app_localizations.dart';
import '../models/audio_item.dart';
import '../providers/audio_library_provider.dart';
import '../services/audio_export_service.dart';
import '../widgets/dialogs/export_audio_dialog.dart';
import '../widgets/manage_subtitles_sheet.dart';
import 'app_data_dir.dart';

/// 懒检测音频内容有效性。
///
/// 用户接触音频（打开学习 / 管理字幕）时才检测，把开销分摊到实际使用。已确认
/// ok 的音频不重复检测；异常状态允许重检，用于修正旧版误报缓存。
void maybeCheckAudioContent(WidgetRef ref, AudioItem item) {
  if (!item.isAudioReady || item.contentStatus == AudioContentStatus.ok) return;
  unawaited(ref.read(audioLibraryProvider.notifier).checkAudioContent(item.id));
}

/// 打开「管理字幕」底部弹窗（进入前懒检测一次内容状态，让转录前拦截能拿到状态）。
void showManageSubtitlesSheet(
  BuildContext context,
  WidgetRef ref,
  AudioItem audioItem,
) {
  maybeCheckAudioContent(ref, audioItem);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => ManageSubtitlesSheet(audioItem: audioItem),
  );
}

/// 导出音频：弹选项对话框（音频文件 / 字幕）→ 生成临时包 → 平台分发保存。
///
/// 字幕内容存 DB 列时先落临时 SRT 供打包，导出后清理；移动端走系统分享，
/// 桌面端走「另存为」文件选择器。
Future<void> exportAudioItem(
  BuildContext context,
  WidgetRef ref,
  AudioItem audioItem,
) async {
  final l10n = AppLocalizations.of(context)!;

  // 1. 弹出导出选项对话框
  final selection = await showExportAudioDialog(
    context: context,
    hasTranscript: audioItem.hasTranscript,
    isVideo: audioItem.isVideo,
  );
  if (selection == null || !context.mounted) return;

  try {
    // 2. 解析文件绝对路径
    final audioPath = await audioItem.getFullAudioPath();
    if (audioPath == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.audioFileNotFound)));
      }
      return;
    }
    // 字幕内容存 DB 列：导出需要文件，故把列内容落临时 SRT 供打包。
    // 旧行（transcriptPath 非 null）仍直接用遗留文件。
    String? transcriptPath = await audioItem.getFullTranscriptPath();
    File? tempTranscriptFile;
    if (selection.includeTranscript && transcriptPath == null) {
      final srt = await ref
          .read(audioItemDaoProvider)
          .getTranscriptSrt(audioItem.id);
      if (srt != null && srt.isNotEmpty) {
        final dataDir = await getAppDataDirectory();
        final tmpDir = Directory(p.join(dataDir.path, 'tmp', 'export'));
        await tmpDir.create(recursive: true);
        tempTranscriptFile = File(
          p.join(tmpDir.path, '${audioItem.id}_export.srt'),
        );
        await tempTranscriptFile.writeAsString(srt);
        transcriptPath = tempTranscriptFile.path;
      }
    }

    // 3. 调用导出服务生成临时文件
    final service = AudioExportService();
    final String exportPath;
    try {
      exportPath = await service.exportAudioItem(
        displayName: audioItem.name,
        audioPath: audioPath,
        transcriptPath: transcriptPath,
        includeAudio: selection.includeAudio,
        includeTranscript: selection.includeTranscript,
      );
    } finally {
      // 清理临时字幕文件（导出服务已把内容打包）
      if (tempTranscriptFile != null) {
        try {
          await tempTranscriptFile.delete();
        } catch (_) {}
      }
    }

    if (!context.mounted) return;

    // 4. 平台分发保存
    if (Platform.isIOS || Platform.isAndroid) {
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(exportPath)],
        sharePositionOrigin: box != null
            ? box.localToGlobal(Offset.zero) & box.size
            : Rect.zero,
      );
    } else {
      final ext = p.extension(exportPath).replaceFirst('.', '');
      final fileName = p.basename(exportPath);
      final home = Platform.environment['HOME'];
      final downloadsDir = home != null ? '$home/Downloads' : null;

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: l10n.exportAudio,
        fileName: fileName,
        initialDirectory: downloadsDir,
        type: FileType.custom,
        allowedExtensions: [ext],
      );
      if (savePath != null) {
        await File(exportPath).copy(savePath);
        if (context.mounted) {
          final savedName = p.basename(savePath);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l10n.exportSuccess}: $savedName')),
          );
        }
      }
    }

    // 5. 清理临时文件
    try {
      await File(exportPath).delete();
    } catch (_) {}
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${l10n.exportAudio}: $e')));
  }
}
