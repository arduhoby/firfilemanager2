import 'dart:async';

import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../theme/app_theme.dart';
import '../persistence/app_preferences.dart';

part 'settings_provider.g.dart';

/// Keys for persisting settings
const _kThemeModeKey = 'settings_theme_mode';
const _kLocaleKey = 'settings_locale';
const _kSinglePanelModeKey = 'settings_single_panel_mode';
const _kBackgroundImagePathKey = 'settings_background_image_path';
const _kBackgroundOpacityKey = 'settings_background_opacity';

const _kFolderColorsKey = 'settings_folder_colors_map';
const _kPlayAnimationSoundsKey = 'settings_play_animation_sounds';
const _kFilePartSizeMbKey = 'settings_file_part_size_mb';

/// Manages app-level settings: theme mode and locale preference.
@Riverpod(keepAlive: true)
class Settings extends _$Settings {
  @override
  SettingsState build() {
    unawaited(_loadSettings());
    return const SettingsState();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await AppPreferences.getInstance();
      final themeModeStr = prefs.getString(_kThemeModeKey);
      final localeStr = prefs.getString(_kLocaleKey);
      final singlePanelStr = prefs.getString(_kSinglePanelModeKey);

      final themeMode = switch (themeModeStr) {
        'light' => AppThemeMode.light,
        'dark' => AppThemeMode.dark,
        _ => AppThemeMode.system,
      };

      final locale = switch (localeStr) {
        'tr' => const Locale('tr'),
        'en' => const Locale('en'),
        _ => null, // null = follow system
      };

      final bgPath = prefs.getString(_kBackgroundImagePathKey);
      final bgOpacity = prefs.getDouble(_kBackgroundOpacityKey) ?? 0.15;
      final playAnimationSounds =
          prefs.getBool(_kPlayAnimationSoundsKey) ?? true;
      final filePartSizeMb = prefs.getInt(_kFilePartSizeMbKey) ?? 95;

      // Load custom folder colors
      final colorsList = prefs.getStringList(_kFolderColorsKey) ?? [];
      final folderColors = <String, int>{};
      for (final item in colorsList) {
        final parts = item.split('::');
        if (parts.length == 2) {
          final colorVal = int.tryParse(parts[1]);
          if (colorVal != null) {
            folderColors[parts[0]] = colorVal;
          }
        }
      }

      state = state.copyWith(
        themeMode: themeMode,
        locale: locale,
        singlePanelMode: singlePanelStr == 'true',
        backgroundImagePath: bgPath,
        backgroundOpacity: bgOpacity,
        folderColors: folderColors,
        playAnimationSounds: playAnimationSounds,
        filePartSizeMb: filePartSizeMb,
        loaded: true,
      );
    } catch (_) {
      state = state.copyWith(loaded: true);
    }
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await AppPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, mode.name);
  }

  Future<void> setSinglePanelMode(bool isSingle) async {
    state = state.copyWith(singlePanelMode: isSingle);
    final prefs = await AppPreferences.getInstance();
    await prefs.setString(_kSinglePanelModeKey, isSingle.toString());
  }

  Future<void> setLocale(Locale? locale) async {
    state = state.copyWith(locale: locale);
    if (locale != null) {
      final prefs = await AppPreferences.getInstance();
      await prefs.setString(_kLocaleKey, locale.languageCode);
    } else {
      final prefs = await AppPreferences.getInstance();
      await prefs.remove(_kLocaleKey);
    }
  }

  Future<void> setBackgroundImagePath(String? path) async {
    state = state.copyWith(
      backgroundImagePath: path,
      clearBackgroundPath: path == null,
    );
    final prefs = await AppPreferences.getInstance();
    if (path != null) {
      await prefs.setString(_kBackgroundImagePathKey, path);
    } else {
      await prefs.remove(_kBackgroundImagePathKey);
    }
  }

  Future<void> setBackgroundOpacity(double opacity) async {
    state = state.copyWith(backgroundOpacity: opacity);
    final prefs = await AppPreferences.getInstance();
    await prefs.setDouble(_kBackgroundOpacityKey, opacity);
  }

  Future<void> setFolderColor(String folderPath, Color? color) async {
    final updatedColors = Map<String, int>.from(state.folderColors);
    if (color == null) {
      updatedColors.remove(folderPath);
    } else {
      updatedColors[folderPath] = color.value;
    }
    state = state.copyWith(folderColors: updatedColors);

    final prefs = await AppPreferences.getInstance();
    final colorsList = updatedColors.entries
        .map((e) => '${e.key}::${e.value}')
        .toList();
    await prefs.setStringList(_kFolderColorsKey, colorsList);
  }

  Future<void> setPlayAnimationSounds(bool playSounds) async {
    state = state.copyWith(playAnimationSounds: playSounds);
    final prefs = await AppPreferences.getInstance();
    await prefs.setBool(_kPlayAnimationSoundsKey, playSounds);
  }

  Future<void> setFilePartSizeMb(int sizeMb) async {
    if (sizeMb <= 0) return;
    state = state.copyWith(filePartSizeMb: sizeMb);
    final prefs = await AppPreferences.getInstance();
    await prefs.setInt(_kFilePartSizeMbKey, sizeMb);
  }
}

/// Immutable state for [Settings]
class SettingsState {
  const SettingsState({
    this.themeMode = AppThemeMode.system,
    this.locale,
    this.singlePanelMode = false,
    this.loaded = false,
    this.backgroundImagePath,
    this.backgroundOpacity = 0.15,
    this.folderColors = const {},
    this.playAnimationSounds = true,
    this.filePartSizeMb = 95,
  });

  final AppThemeMode themeMode;
  final Locale? locale;
  final bool singlePanelMode;
  final bool loaded;
  final String? backgroundImagePath;
  final double backgroundOpacity;
  final Map<String, int> folderColors;
  final bool playAnimationSounds;
  final int filePartSizeMb;

  /// Convert [AppThemeMode] to Flutter's [ThemeMode]
  ThemeMode get flutterThemeMode => switch (themeMode) {
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.system => ThemeMode.system,
  };

  SettingsState copyWith({
    AppThemeMode? themeMode,
    Locale? locale,
    bool? singlePanelMode,
    bool? loaded,
    String? backgroundImagePath,
    bool clearBackgroundPath = false,
    double? backgroundOpacity,
    Map<String, int>? folderColors,
    bool? playAnimationSounds,
    int? filePartSizeMb,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      locale: locale ?? this.locale,
      singlePanelMode: singlePanelMode ?? this.singlePanelMode,
      loaded: loaded ?? this.loaded,
      backgroundImagePath: clearBackgroundPath
          ? null
          : (backgroundImagePath ?? this.backgroundImagePath),
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      folderColors: folderColors ?? this.folderColors,
      playAnimationSounds: playAnimationSounds ?? this.playAnimationSounds,
      filePartSizeMb: filePartSizeMb ?? this.filePartSizeMb,
    );
  }
}
