/// 收藏复习共用调度设置的持久化状态。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/favorite_review_settings.dart';

const _favoriteReviewSettingsKey = 'favorite_review_settings_v1';
const _bookmarkReviewSettingsKey = 'bookmark_review_settings_v1';
const _favoriteVocabularyReviewSettingsKey =
    'favorite_vocabulary_review_settings_v1';

final favoriteReviewSettingsProvider =
    NotifierProvider<FavoriteReviewSettingsNotifier, FavoriteReviewSettings>(
      FavoriteReviewSettingsNotifier.new,
    );

class FavoriteReviewSettingsNotifier extends Notifier<FavoriteReviewSettings> {
  @override
  FavoriteReviewSettings build() {
    _load();
    return const FavoriteReviewSettings();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw =
          prefs.getString(_favoriteReviewSettingsKey) ??
          prefs.getString(_bookmarkReviewSettingsKey) ??
          prefs.getString(_favoriteVocabularyReviewSettingsKey);
      if (raw == null) return;
      final settings = FavoriteReviewSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      state = settings;
      if (!prefs.containsKey(_favoriteReviewSettingsKey)) {
        await prefs.setString(_favoriteReviewSettingsKey, jsonEncode(settings));
      }
    } catch (error) {
      debugPrint('FavoriteReviewSettings: load failed: $error');
    }
  }

  Future<void> update(FavoriteReviewSettings settings) async {
    state = settings;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_favoriteReviewSettingsKey, jsonEncode(settings));
    } catch (error) {
      debugPrint('FavoriteReviewSettings: save failed: $error');
    }
  }
}
