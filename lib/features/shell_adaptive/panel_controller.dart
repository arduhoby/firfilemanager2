import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/settings/recent_service.dart';
import '../../core/storage/storage_provider.dart';
import '../../core/storage/storage_provider_service.dart';
import '../file_operations/file_operations_state.dart';

part 'panel_controller.g.dart';

@Riverpod(keepAlive: true)
class PanelController extends _$PanelController {
  final Map<PanelId, StreamSubscription<FileSystemEvent>> _watchers = {};

  @override
  void build() {
    ref.onDispose(() {
      for (final subscription in _watchers.values) {
        subscription.cancel();
      }
      _watchers.clear();
    });

    ref.listen(panelWorkspaceProvider, (previous, next) {
      for (final removedId
          in _watchers.keys
              .where((panelId) => !next.panels.containsKey(panelId))
              .toList()) {
        _cancelWatcher(removedId);
      }

      for (final panelId in next.panelOrder) {
        final panel = next.panel(panelId).activeTab;
        final previousPanel = previous?.panels[panelId]?.activeTab;
        if (previousPanel == null ||
            previousPanel.currentPath != panel.currentPath ||
            previousPanel.providerId != panel.providerId ||
            previousPanel.showHidden != panel.showHidden) {
          _loadDirectory(panelId, panel.currentPath, panel.showHidden);
        }
      }
    });
  }

  StorageProvider _getProviderForPath(PanelId panelId, String path) {
    final panelState = ref.read(panelWorkspaceProvider).panel(panelId);
    if (panelState.activeTab.providerId == 'local') {
      return ref.read(localStorageProviderProvider);
    }

    final provider = ref.read(
      storageProviderRegistryProvider,
    )[panelState.activeTab.providerId];
    if (provider == null) {
      throw Exception('Connection is not active or disconnected.');
    }
    return provider;
  }

  Future<void> _loadDirectory(
    PanelId panelId,
    String path,
    bool showHidden,
  ) async {
    final workspace = ref.read(panelWorkspaceProvider);
    if (!workspace.panels.containsKey(panelId)) return;

    final panels = ref.read(panelWorkspaceProvider.notifier);
    panels.setLoading(panelId, true);

    try {
      final provider = _getProviderForPath(panelId, path);
      final entries = await provider
          .list(path, ListOptions(showHidden: showHidden))
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw StorageException(
              'Ağ klasörü 30 saniye içinde yanıt vermedi.',
              code: StorageException.timeout,
              path: path,
            ),
          );

      if (!ref.read(panelWorkspaceProvider).panels.containsKey(panelId)) return;
      panels.setEntries(panelId, entries);

      final home = Platform.environment['HOME'];
      if (provider.displayName == 'Local' &&
          (home == null || !path.startsWith('$home/Library/'))) {
        unawaited(
          ref.read(recentServiceProvider.notifier).addRecentFolder(path),
        );
      }

      if (provider.displayName == 'Local') {
        _setupWatcher(panelId, path);
      } else {
        _cancelWatcher(panelId);
      }
    } catch (error) {
      if (ref.read(panelWorkspaceProvider).panels.containsKey(panelId)) {
        panels.setError(panelId, error.toString());
      }
    }
  }

  void _cancelWatcher(PanelId panelId) {
    _watchers.remove(panelId)?.cancel();
  }

  void _setupWatcher(PanelId panelId, String path) {
    _cancelWatcher(panelId);
    try {
      final directory = Directory(path);
      if (!directory.existsSync()) return;
      if (Platform.isWindows && RegExp(r'^[a-zA-Z]:\\?$').hasMatch(path)) {
        return;
      }

      _watchers[panelId] = directory
          .watch(events: FileSystemEvent.all, recursive: false)
          .listen((_) {
            Future.delayed(const Duration(milliseconds: 100), () {
              final panel = ref.read(panelWorkspaceProvider).panels[panelId];
              if (panel?.activeTab.currentPath == path) {
                unawaited(refresh(panelId));
              }
            });
          });
    } catch (_) {
      // File watching is an optional convenience. Directory loading remains
      // authoritative when a platform or mount cannot be watched.
    }
  }

  Future<void> navigate(
    PanelId panelId,
    String path, {
    String? providerId,
  }) async {
    var resolvedProviderId = providerId;
    if (resolvedProviderId == null) {
      final isLocal = Platform.isWindows
          ? RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(path)
          : path.startsWith('/Users/') ||
                path.startsWith('/home/') ||
                path.startsWith('/tmp/') ||
                path.startsWith('/storage/') ||
                path.startsWith('/sdcard') ||
                Directory(path).existsSync();
      if (isLocal) resolvedProviderId = 'local';
    }

    final panels = ref.read(panelWorkspaceProvider.notifier);
    if (resolvedProviderId != null) {
      panels.setProviderAndPath(panelId, resolvedProviderId, path);
    } else {
      panels.setPath(panelId, path);
    }
  }

  Future<void> navigateUp(PanelId panelId) async {
    final panelState = ref.read(panelWorkspaceProvider).panel(panelId);
    final currentPath = panelState.activeTab.currentPath;
    final provider = _getProviderForPath(panelId, currentPath);
    final parent = provider.dirname(currentPath);
    if (parent == currentPath) return;
    if (Platform.isWindows &&
        RegExp(r'^[a-zA-Z]:\\?$').hasMatch(currentPath.replaceAll('/', '\\'))) {
      return;
    }
    await navigate(panelId, parent);
  }

  Future<void> navigateBack(PanelId panelId) async {
    ref.read(panelWorkspaceProvider.notifier).goBack(panelId);
  }

  Future<void> navigateHome(PanelId panelId) async {
    final panelState = ref.read(panelWorkspaceProvider).panel(panelId);
    try {
      final provider = _getProviderForPath(
        panelId,
        panelState.activeTab.currentPath,
      );
      final home = await provider.homePath;
      await navigate(
        panelId,
        home,
        providerId: panelState.activeTab.providerId,
      );
    } catch (_) {
      try {
        final localProvider = ref.read(localStorageProviderProvider);
        await navigate(
          panelId,
          await localProvider.homePath,
          providerId: 'local',
        );
      } catch (_) {}
    }
  }

  Future<void> navigateForward(PanelId panelId) async {
    ref.read(panelWorkspaceProvider.notifier).goForward(panelId);
  }

  Future<void> refresh(PanelId panelId) async {
    final panelState = ref.read(panelWorkspaceProvider).panel(panelId);
    await _loadDirectory(
      panelId,
      panelState.activeTab.currentPath,
      panelState.activeTab.showHidden,
    );
  }

  Future<void> search(
    PanelId panelId,
    String query, {
    bool recursive = false,
  }) async {
    final panelState = ref.read(panelWorkspaceProvider).panel(panelId);
    if (query.trim().isEmpty) {
      await refresh(panelId);
      return;
    }

    final panels = ref.read(panelWorkspaceProvider.notifier);
    panels.setLoading(panelId, true);
    try {
      final provider = _getProviderForPath(
        panelId,
        panelState.activeTab.currentPath,
      );
      final results = await provider.search(
        panelState.activeTab.currentPath,
        query,
        recursive: recursive,
      );
      panels.setEntries(panelId, results);
    } catch (error) {
      panels.setError(panelId, error.toString());
    }
  }

  Future<void> initialize() async {
    try {
      final provider = ref.read(localStorageProviderProvider);
      final home = await provider.homePath;
      final panels = ref.read(panelWorkspaceProvider.notifier);
      for (final panelId in ref.read(panelWorkspaceProvider).panelOrder) {
        panels.setPath(panelId, home);
      }
    } catch (_) {}
  }
}
