import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../persistence/app_preferences.dart';

part 'recent_service.g.dart';

const _kRecentAppsKey = 'recent_apps';
const _kRecentFoldersKey = 'recent_folders';
const _kRecentFilesKey = 'recent_files';

const _kMaxRecentItems = 15;

/// Service to manage recent apps, folders, and files.
@Riverpod(keepAlive: true)
class RecentService extends _$RecentService {
  @override
  RecentState build() {
    unawaited(_loadRecents());
    return const RecentState();
  }

  Future<void> _loadRecents() async {
    final prefs = await AppPreferences.getInstance();
    final apps = prefs.getStringList(_kRecentAppsKey) ?? [];
    final folders = prefs.getStringList(_kRecentFoldersKey) ?? [];
    final files = prefs.getStringList(_kRecentFilesKey) ?? [];

    state = RecentState(
      recentApps: apps,
      recentFolders: folders,
      recentFiles: files,
    );
  }

  /// Add a recent app
  Future<void> addRecentApp(String path) async {
    final newList = _addToRecentList(state.recentApps, path);
    state = state.copyWith(recentApps: newList);
    final prefs = await AppPreferences.getInstance();
    await prefs.setStringList(_kRecentAppsKey, newList);
  }

  /// Add a recent folder
  Future<void> addRecentFolder(String path) async {
    final newList = _addToRecentList(state.recentFolders, path);
    state = state.copyWith(recentFolders: newList);
    final prefs = await AppPreferences.getInstance();
    await prefs.setStringList(_kRecentFoldersKey, newList);
  }

  /// Add a recent file
  Future<void> addRecentFile(String path) async {
    final newList = _addToRecentList(state.recentFiles, path);
    state = state.copyWith(recentFiles: newList);
    final prefs = await AppPreferences.getInstance();
    await prefs.setStringList(_kRecentFilesKey, newList);
  }

  /// Clear all recents (optional utility)
  Future<void> clearAll() async {
    state = const RecentState();
    final prefs = await AppPreferences.getInstance();
    await prefs.remove(_kRecentAppsKey);
    await prefs.remove(_kRecentFoldersKey);
    await prefs.remove(_kRecentFilesKey);
  }

  List<String> _addToRecentList(List<String> currentList, String newItem) {
    final list = List<String>.from(currentList);
    list.remove(newItem); // Remove if already exists to move to top
    list.insert(0, newItem);
    if (list.length > _kMaxRecentItems) {
      return list.sublist(0, _kMaxRecentItems);
    }
    return list;
  }
}

class RecentState {
  final List<String> recentApps;
  final List<String> recentFolders;
  final List<String> recentFiles;

  const RecentState({
    this.recentApps = const [],
    this.recentFolders = const [],
    this.recentFiles = const [],
  });

  RecentState copyWith({
    List<String>? recentApps,
    List<String>? recentFolders,
    List<String>? recentFiles,
  }) {
    return RecentState(
      recentApps: recentApps ?? this.recentApps,
      recentFolders: recentFolders ?? this.recentFolders,
      recentFiles: recentFiles ?? this.recentFiles,
    );
  }
}
