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
    this.convertQuality = 75,
    this.convertOnlyIfSmaller = true,
    this.convertSkipExistingWebp = true,
    this.convertRemoveComicInfo = true,
    this.convertRenumber = true,
  });

  final ThemeMode themeMode;

  /// Empty = follow the system locale.
  final String languageCode;
  final int convertThreads;
  final int mergeThreads;
  final int cbrThreads;
  final int batchThreads;
  final bool backupByDefault;

  /// WebP conversion options, persisted like the reference dialog.
  final int convertQuality;
  final bool convertOnlyIfSmaller;
  final bool convertSkipExistingWebp;
  final bool convertRemoveComicInfo;
  final bool convertRenumber;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? languageCode,
    int? convertThreads,
    int? mergeThreads,
    int? cbrThreads,
    int? batchThreads,
    bool? backupByDefault,
    int? convertQuality,
    bool? convertOnlyIfSmaller,
    bool? convertSkipExistingWebp,
    bool? convertRemoveComicInfo,
    bool? convertRenumber,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    languageCode: languageCode ?? this.languageCode,
    convertThreads: convertThreads ?? this.convertThreads,
    mergeThreads: mergeThreads ?? this.mergeThreads,
    cbrThreads: cbrThreads ?? this.cbrThreads,
    batchThreads: batchThreads ?? this.batchThreads,
    backupByDefault: backupByDefault ?? this.backupByDefault,
    convertQuality: convertQuality ?? this.convertQuality,
    convertOnlyIfSmaller: convertOnlyIfSmaller ?? this.convertOnlyIfSmaller,
    convertSkipExistingWebp:
        convertSkipExistingWebp ?? this.convertSkipExistingWebp,
    convertRemoveComicInfo:
        convertRemoveComicInfo ?? this.convertRemoveComicInfo,
    convertRenumber: convertRenumber ?? this.convertRenumber,
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
  static const _convertQualityKey = 'convertQuality';
  static const _convertOnlyIfSmallerKey = 'convertOnlyIfSmaller';
  static const _convertSkipExistingWebpKey = 'convertSkipExistingWebp';
  static const _convertRemoveComicInfoKey = 'convertRemoveComicInfo';
  static const _convertRenumberKey = 'convertRenumber';

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
      convertQuality: prefs.getInt(_convertQualityKey) ?? 75,
      convertOnlyIfSmaller: prefs.getBool(_convertOnlyIfSmallerKey) ?? true,
      convertSkipExistingWebp:
          prefs.getBool(_convertSkipExistingWebpKey) ?? true,
      convertRemoveComicInfo: prefs.getBool(_convertRemoveComicInfoKey) ?? true,
      convertRenumber: prefs.getBool(_convertRenumberKey) ?? true,
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
    await prefs.setInt(_convertQualityKey, settings.convertQuality);
    await prefs.setBool(
      _convertOnlyIfSmallerKey,
      settings.convertOnlyIfSmaller,
    );
    await prefs.setBool(
      _convertSkipExistingWebpKey,
      settings.convertSkipExistingWebp,
    );
    await prefs.setBool(
      _convertRemoveComicInfoKey,
      settings.convertRemoveComicInfo,
    );
    await prefs.setBool(_convertRenumberKey, settings.convertRenumber);
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
