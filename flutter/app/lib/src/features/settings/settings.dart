import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences instance, injected in `main` before the app starts.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider not overridden'),
);

/// Persisted application settings.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.languageCode = '',
    this.convertThreads = 0,
    this.mergeThreads = 0,
    this.cbrThreads = 0,
    this.batchThreads = 0,
    this.backupByDefault = true,
  });

  final ThemeMode themeMode;

  /// Empty = follow the system locale.
  final String languageCode;
  final int convertThreads;
  final int mergeThreads;
  final int cbrThreads;
  final int batchThreads;
  final bool backupByDefault;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? languageCode,
    int? convertThreads,
    int? mergeThreads,
    int? cbrThreads,
    int? batchThreads,
    bool? backupByDefault,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        languageCode: languageCode ?? this.languageCode,
        convertThreads: convertThreads ?? this.convertThreads,
        mergeThreads: mergeThreads ?? this.mergeThreads,
        cbrThreads: cbrThreads ?? this.cbrThreads,
        batchThreads: batchThreads ?? this.batchThreads,
        backupByDefault: backupByDefault ?? this.backupByDefault,
      );
}

/// Reads/writes [AppSettings] from [sharedPrefsProvider].
class SettingsController extends Notifier<AppSettings> {
  static const _themeKey = 'themeMode';
  static const _langKey = 'languageCode';
  static const _convertKey = 'convertThreads';
  static const _mergeKey = 'mergeThreads';
  static const _cbrKey = 'cbrThreads';
  static const _batchKey = 'batchThreads';
  static const _backupKey = 'backupByDefault';

  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  @override
  AppSettings build() {
    final prefs = _prefs;
    return AppSettings(
      themeMode: _themeFromName(prefs.getString(_themeKey)),
      languageCode: prefs.getString(_langKey) ?? '',
      convertThreads: prefs.getInt(_convertKey) ?? 0,
      mergeThreads: prefs.getInt(_mergeKey) ?? 0,
      cbrThreads: prefs.getInt(_cbrKey) ?? 0,
      batchThreads: prefs.getInt(_batchKey) ?? 0,
      backupByDefault: prefs.getBool(_backupKey) ?? true,
    );
  }

  Future<void> update(AppSettings settings) async {
    state = settings;
    final prefs = _prefs;
    await prefs.setString(_themeKey, settings.themeMode.name);
    await prefs.setString(_langKey, settings.languageCode);
    await prefs.setInt(_convertKey, settings.convertThreads);
    await prefs.setInt(_mergeKey, settings.mergeThreads);
    await prefs.setInt(_cbrKey, settings.cbrThreads);
    await prefs.setInt(_batchKey, settings.batchThreads);
    await prefs.setBool(_backupKey, settings.backupByDefault);
  }

  static ThemeMode _themeFromName(String? name) {
    switch (name) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
