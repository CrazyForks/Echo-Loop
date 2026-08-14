/// 收藏句 FSRS 复习设置状态管理。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bookmark_review_settings.dart';

const _bookmarkReviewSettingsKey = 'bookmark_review_settings_v1';

final bookmarkReviewSettingsProvider =
    NotifierProvider<BookmarkReviewSettingsNotifier, BookmarkReviewSettings>(
      BookmarkReviewSettingsNotifier.new,
    );

class BookmarkReviewSettingsNotifier extends Notifier<BookmarkReviewSettings> {
  @override
  BookmarkReviewSettings build() {
    _load();
    return const BookmarkReviewSettings();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_bookmarkReviewSettingsKey);
      if (raw != null) {
        state = BookmarkReviewSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
    } catch (error) {
      debugPrint('BookmarkReviewSettings: load failed: $error');
    }
  }

  Future<void> update(BookmarkReviewSettings settings) async {
    state = settings;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _bookmarkReviewSettingsKey,
        jsonEncode(settings.toJson()),
      );
    } catch (error) {
      debugPrint('BookmarkReviewSettings: save failed: $error');
    }
  }
}
