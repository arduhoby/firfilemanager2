import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/persistence/app_preferences.dart';
import '../../core/storage/models/file_entry.dart';
import '../../core/storage/models/transfer_progress.dart';

part 'file_operations_state.g.dart';

@immutable
class PanelId {
  const PanelId(this.value);

  static const a = PanelId('panel-a');
  static const b = PanelId('panel-b');

  final String value;

  @override
  bool operator ==(Object other) => other is PanelId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

enum SortField { name, date, size, type }

enum SortDirection { ascending, descending }

class TabState {
  const TabState({
    required this.id,
    required this.currentPath,
    this.providerId = 'local',
    this.entries = const [],
    this.selectedPaths = const {},
    this.sortField = SortField.name,
    this.sortDirection = SortDirection.ascending,
    this.showHidden = false,
    this.isLoading = false,
    this.searchQuery,
    this.error,
    this.history = const [],
    this.historyIndex = -1,
  });

  final String id;
  final String currentPath;
  final String providerId;
  final List<FileEntry> entries;
  final Set<String> selectedPaths;
  final SortField sortField;
  final SortDirection sortDirection;
  final bool showHidden;
  final bool isLoading;
  final String? searchQuery;
  final String? error;
  final List<String> history;
  final int historyIndex;

  List<FileEntry> get selectedEntries =>
      entries.where((entry) => selectedPaths.contains(entry.path)).toList();

  bool get hasSelection => selectedPaths.isNotEmpty;

  int get selectionCount => selectedPaths.length;

  TabState copyWith({
    String? currentPath,
    String? providerId,
    List<FileEntry>? entries,
    Set<String>? selectedPaths,
    SortField? sortField,
    SortDirection? sortDirection,
    bool? showHidden,
    bool? isLoading,
    String? searchQuery,
    bool clearSearchQuery = false,
    String? error,
    List<String>? history,
    int? historyIndex,
  }) {
    return TabState(
      id: id,
      currentPath: currentPath ?? this.currentPath,
      providerId: providerId ?? this.providerId,
      entries: entries ?? this.entries,
      selectedPaths: selectedPaths ?? this.selectedPaths,
      sortField: sortField ?? this.sortField,
      sortDirection: sortDirection ?? this.sortDirection,
      showHidden: showHidden ?? this.showHidden,
      isLoading: isLoading ?? this.isLoading,
      searchQuery: clearSearchQuery ? null : (searchQuery ?? this.searchQuery),
      error: error,
      history: history ?? this.history,
      historyIndex: historyIndex ?? this.historyIndex,
    );
  }
}

class PanelState {
  const PanelState({required this.tabs, this.activeTabIndex = 0});

  factory PanelState.initial({
    String path = '/',
    String providerId = 'local',
  }) => PanelState(
    tabs: [TabState(id: 'tab_0', currentPath: path, providerId: providerId)],
  );

  final List<TabState> tabs;
  final int activeTabIndex;

  TabState get activeTab => tabs.isNotEmpty
      ? tabs[activeTabIndex]
      : const TabState(id: 'default', currentPath: '/');

  PanelState copyWith({List<TabState>? tabs, int? activeTabIndex}) {
    return PanelState(
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
    );
  }
}

class PanelWorkspaceState {
  const PanelWorkspaceState({
    required this.panelOrder,
    required this.panels,
    required this.activePanelId,
    required this.nextPanelSequence,
  });

  factory PanelWorkspaceState.initial() => PanelWorkspaceState(
    panelOrder: const [PanelId.a, PanelId.b],
    panels: {PanelId.a: PanelState.initial(), PanelId.b: PanelState.initial()},
    activePanelId: PanelId.a,
    nextPanelSequence: 2,
  );

  static const minPanelCount = 2;
  static const maxPanelCount = 5;

  final List<PanelId> panelOrder;
  final Map<PanelId, PanelState> panels;
  final PanelId activePanelId;
  final int nextPanelSequence;

  int get panelCount => panelOrder.length;
  bool get canAddPanel => panelCount < maxPanelCount;
  bool get canRemovePanel => panelCount > minPanelCount;
  List<PanelId> get destinationPanelIds => panelOrder
      .where((panelId) => panelId != activePanelId)
      .toList(growable: false);

  PanelState panel(PanelId panelId) {
    final panel = panels[panelId];
    if (panel == null) {
      throw StateError('Unknown panel: $panelId');
    }
    return panel;
  }

  PanelWorkspaceState copyWith({
    List<PanelId>? panelOrder,
    Map<PanelId, PanelState>? panels,
    PanelId? activePanelId,
    int? nextPanelSequence,
  }) {
    return PanelWorkspaceState(
      panelOrder: panelOrder ?? this.panelOrder,
      panels: panels ?? this.panels,
      activePanelId: activePanelId ?? this.activePanelId,
      nextPanelSequence: nextPanelSequence ?? this.nextPanelSequence,
    );
  }
}

final panelStateProvider = Provider.family<PanelState, PanelId>((ref, panelId) {
  return ref.watch(
    panelWorkspaceProvider.select(
      (workspace) =>
          workspace.panels[panelId] ??
          const PanelState(
            tabs: [TabState(id: 'removed', currentPath: '/')],
          ),
    ),
  );
});

final activePanelProvider = Provider<PanelId>((ref) {
  return ref.watch(
    panelWorkspaceProvider.select((workspace) => workspace.activePanelId),
  );
});

@Riverpod(keepAlive: true)
class PanelWorkspace extends _$PanelWorkspace {
  static const _panelCountPreferenceKey = 'workspace_panel_count';

  bool _persistenceReady = false;

  @override
  PanelWorkspaceState build() => PanelWorkspaceState.initial();

  Future<void> restorePanelCount() async {
    final preferences = await AppPreferences.getInstance();
    final savedCount = int.tryParse(
      preferences.getString(_panelCountPreferenceKey) ?? '',
    );
    if (savedCount != null) {
      setPanelCount(savedCount, persist: false);
    }
    _persistenceReady = true;
  }

  Future<void> persistPanelCount() async {
    final preferences = await AppPreferences.getInstance();
    await preferences.setString(
      _panelCountPreferenceKey,
      state.panelCount.toString(),
    );
  }

  void setPanelCount(int panelCount, {bool persist = true}) {
    final previousActivePanelId = state.activePanelId;
    final targetCount = panelCount.clamp(
      PanelWorkspaceState.minPanelCount,
      PanelWorkspaceState.maxPanelCount,
    );

    while (state.panelCount < targetCount) {
      _addPanel(path: '/', providerId: 'local');
    }
    while (state.panelCount > targetCount) {
      _removePanel(state.panelOrder.last);
    }

    state = state.copyWith(
      activePanelId: state.panels.containsKey(previousActivePanelId)
          ? previousActivePanelId
          : state.panelOrder.first,
    );
    if (persist) _persistPanelCountIfReady();
  }

  PanelId addPanel({String path = '/', String providerId = 'local'}) {
    if (!state.canAddPanel) {
      throw StateError(
        'A maximum of ${PanelWorkspaceState.maxPanelCount} panels is supported.',
      );
    }

    final panelId = _addPanel(path: path, providerId: providerId);
    _persistPanelCountIfReady();
    return panelId;
  }

  PanelId _addPanel({required String path, required String providerId}) {
    final sequence = state.nextPanelSequence + 1;
    final panelId = PanelId('panel-$sequence');
    state = state.copyWith(
      panelOrder: [...state.panelOrder, panelId],
      panels: {
        ...state.panels,
        panelId: PanelState.initial(path: path, providerId: providerId),
      },
      activePanelId: panelId,
      nextPanelSequence: sequence,
    );
    return panelId;
  }

  bool removePanel(PanelId panelId) {
    if (!state.canRemovePanel || !state.panels.containsKey(panelId)) {
      return false;
    }

    _removePanel(panelId);
    _persistPanelCountIfReady();
    return true;
  }

  void _removePanel(PanelId panelId) {
    final panelOrder = [...state.panelOrder]..remove(panelId);
    final panels = Map<PanelId, PanelState>.from(state.panels)..remove(panelId);
    state = state.copyWith(
      panelOrder: panelOrder,
      panels: panels,
      activePanelId: state.activePanelId == panelId
          ? panelOrder.first
          : state.activePanelId,
    );
  }

  void _persistPanelCountIfReady() {
    if (_persistenceReady) unawaited(persistPanelCount());
  }

  void reorderPanels(List<PanelId> panelOrder) {
    if (panelOrder.length != state.panelOrder.length ||
        panelOrder.toSet().length != panelOrder.length ||
        !panelOrder.toSet().containsAll(state.panelOrder)) {
      throw ArgumentError('Panel order must contain every panel exactly once.');
    }
    state = state.copyWith(panelOrder: List.unmodifiable(panelOrder));
  }

  void setActive(PanelId panelId) {
    if (state.panels.containsKey(panelId)) {
      state = state.copyWith(activePanelId: panelId);
    }
  }

  void setPath(PanelId panelId, String path) {
    _updateActiveTab(panelId, (tab) {
      if (tab.currentPath == path) return tab;
      final history = tab.historyIndex >= 0
          ? tab.history.sublist(0, tab.historyIndex + 1)
          : <String>[tab.currentPath];
      history.add(path);
      return tab.copyWith(
        currentPath: path,
        selectedPaths: {},
        error: null,
        history: history,
        historyIndex: history.length - 1,
      );
    });
  }

  void setProviderAndPath(PanelId panelId, String providerId, String path) {
    _updateActiveTab(panelId, (tab) {
      if (tab.currentPath == path && tab.providerId == providerId) return tab;
      final history = tab.historyIndex >= 0
          ? tab.history.sublist(0, tab.historyIndex + 1)
          : <String>[tab.currentPath];
      history.add(path);
      return tab.copyWith(
        providerId: providerId,
        currentPath: path,
        selectedPaths: {},
        error: null,
        history: history,
        historyIndex: history.length - 1,
      );
    });
  }

  void goBack(PanelId panelId) {
    _updateActiveTab(panelId, (tab) {
      if (tab.historyIndex <= 0) return tab;
      final historyIndex = tab.historyIndex - 1;
      return tab.copyWith(
        currentPath: tab.history[historyIndex],
        selectedPaths: {},
        error: null,
        historyIndex: historyIndex,
      );
    });
  }

  void goForward(PanelId panelId) {
    _updateActiveTab(panelId, (tab) {
      if (tab.historyIndex < 0 || tab.historyIndex >= tab.history.length - 1) {
        return tab;
      }
      final historyIndex = tab.historyIndex + 1;
      return tab.copyWith(
        currentPath: tab.history[historyIndex],
        selectedPaths: {},
        error: null,
        historyIndex: historyIndex,
      );
    });
  }

  void setEntries(PanelId panelId, List<FileEntry> entries) {
    final panel = state.panel(panelId);
    final sorted = _sortEntries(
      entries,
      panel.activeTab.sortField,
      panel.activeTab.sortDirection,
    );
    _updateActiveTab(
      panelId,
      (tab) => tab.copyWith(entries: sorted, isLoading: false),
    );
  }

  void setLoading(PanelId panelId, bool loading) {
    _updateActiveTab(panelId, (tab) => tab.copyWith(isLoading: loading));
  }

  void setSearchQuery(PanelId panelId, String? query) {
    _updateActiveTab(
      panelId,
      (tab) =>
          tab.copyWith(searchQuery: query, clearSearchQuery: query == null),
    );
  }

  void setError(PanelId panelId, String? error) {
    _updateActiveTab(
      panelId,
      (tab) => tab.copyWith(error: error, isLoading: false),
    );
  }

  void selectEntry(PanelId panelId, String path) {
    _updateActiveTab(panelId, (tab) => tab.copyWith(selectedPaths: {path}));
  }

  void toggleSelection(PanelId panelId, String path) {
    _updateActiveTab(panelId, (tab) {
      final selection = Set<String>.from(tab.selectedPaths);
      selection.contains(path) ? selection.remove(path) : selection.add(path);
      return tab.copyWith(selectedPaths: selection);
    });
  }

  void selectRange(PanelId panelId, String from, String to) {
    _updateActiveTab(panelId, (tab) {
      final fromIndex = tab.entries.indexWhere((entry) => entry.path == from);
      final toIndex = tab.entries.indexWhere((entry) => entry.path == to);
      if (fromIndex == -1 || toIndex == -1) return tab;

      final start = fromIndex < toIndex ? fromIndex : toIndex;
      final end = fromIndex < toIndex ? toIndex : fromIndex;
      return tab.copyWith(
        selectedPaths: {
          for (var index = start; index <= end; index++)
            tab.entries[index].path,
        },
      );
    });
  }

  void clearSelection(PanelId panelId) {
    _updateActiveTab(panelId, (tab) => tab.copyWith(selectedPaths: {}));
  }

  void selectAll(PanelId panelId) {
    _updateActiveTab(
      panelId,
      (tab) => tab.copyWith(
        selectedPaths: tab.entries.map((entry) => entry.path).toSet(),
      ),
    );
  }

  void toggleSort(PanelId panelId, SortField field) {
    _updateActiveTab(panelId, (tab) {
      var direction = SortDirection.ascending;
      if (tab.sortField == field) {
        direction = tab.sortDirection == SortDirection.ascending
            ? SortDirection.descending
            : SortDirection.ascending;
      }
      return tab.copyWith(
        sortField: field,
        sortDirection: direction,
        entries: _sortEntries(tab.entries, field, direction),
      );
    });
  }

  void toggleHidden(PanelId panelId) {
    _updateActiveTab(
      panelId,
      (tab) => tab.copyWith(showHidden: !tab.showHidden),
    );
  }

  void addTab(PanelId panelId, String path, {String providerId = 'local'}) {
    final panel = state.panel(panelId);
    if (panel.tabs.length >= 10) return;

    final tabs = [
      ...panel.tabs,
      TabState(
        id: 'tab_${DateTime.now().microsecondsSinceEpoch}',
        currentPath: path,
        providerId: providerId,
      ),
    ];
    _updatePanel(
      panelId,
      panel.copyWith(tabs: tabs, activeTabIndex: tabs.length - 1),
    );
  }

  void closeTab(PanelId panelId, int index) {
    final panel = state.panel(panelId);
    if (panel.tabs.length <= 1 || index < 0 || index >= panel.tabs.length) {
      return;
    }

    final tabs = [...panel.tabs]..removeAt(index);
    var activeIndex = panel.activeTabIndex;
    if (index < activeIndex) {
      activeIndex--;
    } else if (index == activeIndex && activeIndex >= tabs.length) {
      activeIndex = tabs.length - 1;
    }
    _updatePanel(
      panelId,
      panel.copyWith(tabs: tabs, activeTabIndex: activeIndex),
    );
  }

  void setActiveTab(PanelId panelId, int index) {
    final panel = state.panel(panelId);
    if (index >= 0 && index < panel.tabs.length) {
      _updatePanel(panelId, panel.copyWith(activeTabIndex: index));
    }
  }

  void _updateActiveTab(
    PanelId panelId,
    TabState Function(TabState tab) update,
  ) {
    final panel = state.panel(panelId);
    if (panel.tabs.isEmpty) return;
    final tabs = [...panel.tabs];
    tabs[panel.activeTabIndex] = update(panel.activeTab);
    _updatePanel(panelId, panel.copyWith(tabs: tabs));
  }

  void _updatePanel(PanelId panelId, PanelState panel) {
    state = state.copyWith(panels: {...state.panels, panelId: panel});
  }

  List<FileEntry> _sortEntries(
    List<FileEntry> entries,
    SortField field,
    SortDirection direction,
  ) {
    final sorted = List<FileEntry>.from(entries);
    sorted.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;

      final comparison = switch (field) {
        SortField.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        SortField.date => (a.modified ?? DateTime(1970)).compareTo(
          b.modified ?? DateTime(1970),
        ),
        SortField.size => a.size.compareTo(b.size),
        SortField.type =>
          a.name
              .split('.')
              .last
              .toLowerCase()
              .compareTo(b.name.split('.').last.toLowerCase()),
      };
      return direction == SortDirection.ascending ? comparison : -comparison;
    });
    return sorted;
  }
}

enum ClipboardOperation { copy, cut }

class ClipboardState {
  const ClipboardState({
    required this.sourcePaths,
    required this.sourcePanelId,
    required this.sourceProviderId,
    required this.operation,
  });

  final List<String> sourcePaths;
  final PanelId sourcePanelId;
  final String sourceProviderId;
  final ClipboardOperation operation;
}

@Riverpod(keepAlive: true)
class FileClipboard extends _$FileClipboard {
  @override
  ClipboardState? build() => null;

  void copy(List<String> paths, PanelId panelId, String providerId) {
    state = ClipboardState(
      sourcePaths: paths,
      sourcePanelId: panelId,
      sourceProviderId: providerId,
      operation: ClipboardOperation.copy,
    );
  }

  void cut(List<String> paths, PanelId panelId, String providerId) {
    state = ClipboardState(
      sourcePaths: paths,
      sourcePanelId: panelId,
      sourceProviderId: providerId,
      operation: ClipboardOperation.cut,
    );
  }

  void clear() => state = null;
}

@Riverpod(keepAlive: true)
class OperationProgress extends _$OperationProgress {
  @override
  TransferProgress? build() => null;

  void setProgress(TransferProgress state) => this.state = state;

  void clear() => state = null;
}
