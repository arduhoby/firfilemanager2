import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart' as gen;
import '../../core/theme/glass_container.dart';
import '../bookmarks/bookmarks_menu.dart';
import '../file_operations/file_operations_state.dart';
import 'file_operations_actions.dart';
import 'panel_controller.dart';

/// A hybrid breadcrumb and editable text field for navigating paths.
class PanelPathBar extends ConsumerStatefulWidget {
  const PanelPathBar({required this.side, super.key});

  final PanelId side;

  @override
  ConsumerState<PanelPathBar> createState() => _PanelPathBarState();
}

class _PanelPathBarState extends ConsumerState<PanelPathBar> {
  bool _isEditing = false;
  bool _isSearching = false;
  Timer? _debounce;
  late TextEditingController _addressController;
  late TextEditingController _searchController;
  final FocusNode _focusNode = FocusNode();
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController();
    _searchController = TextEditingController();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) {
        setState(() => _isEditing = false);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _addressController.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  PanelState get _state => ref.watch(panelStateProvider(widget.side));

  PanelWorkspace get _panels => ref.read(panelWorkspaceProvider.notifier);

  void _navigateToAddress() {
    final path = _addressController.text.trim();
    if (path.isNotEmpty) {
      ref.read(panelControllerProvider.notifier).navigate(widget.side, path);
    }
    setState(() {
      _isEditing = false;
      _hasError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = gen.AppLocalizations.of(context)!;
    final state = _state;
    final theme = Theme.of(context);

    // If the controller reports an error (e.g. invalid path), keep the bar open with error state
    if (state.activeTab.error != null &&
        !_isEditing &&
        _addressController.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isEditing = true;
            _hasError = true;
          });
          _focusNode.requestFocus();
        }
      });
    } else if (state.activeTab.error == null && _hasError) {
      // Clear error state if no error
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _hasError = false;
          });
        }
      });
    }

    if (_isSearching) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchController.clear();
                });

                _panels.setSearchQuery(widget.side, null);

                ref.read(panelControllerProvider.notifier).refresh(widget.side);
              },
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () {
                    setState(() {
                      _isSearching = false;
                      _searchController.clear();
                    });
                    _panels.setSearchQuery(widget.side, null);
                    ref
                        .read(panelControllerProvider.notifier)
                        .refresh(widget.side);
                  },
                },
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: theme.textTheme.bodySmall,
                  decoration: InputDecoration(
                    hintText: 'Search files...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: theme.colorScheme.primary),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: theme.dividerColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                    prefixIcon: const Icon(Icons.search, size: 16),
                  ),
                  onChanged: (val) {
                    if (_debounce?.isActive ?? false) _debounce!.cancel();

                    _panels.setSearchQuery(
                      widget.side,
                      val.isEmpty ? null : val,
                    );

                    _debounce = Timer(const Duration(milliseconds: 500), () {
                      ref
                          .read(panelControllerProvider.notifier)
                          .search(widget.side, val, recursive: true);
                    });
                  },
                  onSubmitted: (val) {
                    _debounce?.cancel();
                    _panels.setSearchQuery(
                      widget.side,
                      val.isEmpty ? null : val,
                    );
                    ref
                        .read(panelControllerProvider.notifier)
                        .search(widget.side, val, recursive: true);
                  },
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_isEditing) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() {
                _isEditing = false;
                _hasError = false;
              }),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () {
                    setState(() {
                      _isEditing = false;
                      _hasError = false;
                    });
                  },
                },
                child: TextField(
                  controller: _addressController,
                  focusNode: _focusNode,
                  autofocus: true,
                  style: theme.textTheme.bodySmall,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: _hasError
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: _hasError
                            ? theme.colorScheme.error
                            : theme.dividerColor,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: _hasError
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _navigateToAddress(),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.check, size: 18),
              onPressed: _navigateToAddress,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      );
    }

    final path = state.activeTab.currentPath;
    // Windows paths use \ separator, Unix paths use /. Split by both.
    final isWindowsPath = Platform.isWindows && path.contains('\\');
    final separator = isWindowsPath ? '\\' : '/';
    final segments = path
        .split(RegExp(r'[\\/]'))
        .where((s) => s.isNotEmpty)
        .toList();

    // Reconstruct a path up to segment index i (1-based)
    String buildPathUpTo(int segIndex) {
      final parts = segments.take(segIndex + 1).toList();
      if (isWindowsPath) {
        // e.g. ['C:', 'Users'] -> 'C:\Users'
        return parts.join('\\');
      } else {
        // e.g. ['Users', 'melih'] -> '/Users/melih'
        return '/${parts.join('/')}';
      }
    }

    return GlassContainer(
      borderRadius: BorderRadius.zero,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      showBorder: false,
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 18),
            tooltip: 'Back',
            onPressed: state.activeTab.historyIndex > 0
                ? () {
                    ref
                        .read(panelControllerProvider.notifier)
                        .navigateBack(widget.side);
                  }
                : null,
            visualDensity: VisualDensity.compact,
            color: state.activeTab.historyIndex > 0
                ? null
                : theme.disabledColor,
          ),
          // Forward button
          IconButton(
            icon: const Icon(Icons.arrow_forward, size: 18),
            tooltip: 'Forward',
            onPressed:
                state.activeTab.historyIndex >= 0 &&
                    state.activeTab.historyIndex <
                        state.activeTab.history.length - 1
                ? () {
                    ref
                        .read(panelControllerProvider.notifier)
                        .navigateForward(widget.side);
                  }
                : null,
            visualDensity: VisualDensity.compact,
            color:
                state.activeTab.historyIndex >= 0 &&
                    state.activeTab.historyIndex <
                        state.activeTab.history.length - 1
                ? null
                : theme.disabledColor,
          ),
          // Up button
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 18),
            tooltip: 'Up',
            onPressed: () {
              ref
                  .read(panelControllerProvider.notifier)
                  .navigateUp(widget.side);
            },
            visualDensity: VisualDensity.compact,
          ),
          // Breadcrumb
          Expanded(
            child: GestureDetector(
              onTap: () {
                _addressController.text = state.activeTab.currentPath;
                setState(() => _isEditing = true);
                _focusNode.requestFocus();
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.text,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () {
                          ref
                              .read(panelControllerProvider.notifier)
                              .navigateHome(widget.side);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Icon(
                            Icons.home,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      for (var i = 0; i < segments.length; i++) ...[
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        InkWell(
                          onTap: () {
                            final targetPath = buildPathUpTo(i);
                            ref
                                .read(panelControllerProvider.notifier)
                                .navigate(widget.side, targetPath);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            child: Text(
                              segments[i],
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                      // Empty space to ensure the text cursor appears when clicking on the right
                      const SizedBox(width: 100),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Bookmarks
          BookmarksMenuIcon(side: widget.side),
          // Sync
          IconButton(
            icon: const Icon(Icons.sync, size: 18),
            tooltip: 'Synchronize to other panel',
            onPressed: () {
              ref
                  .read(fileOperationsActionsProvider.notifier)
                  .syncPanels(context, widget.side);
            },
            visualDensity: VisualDensity.compact,
          ),
          // Search
          IconButton(
            icon: const Icon(Icons.search, size: 18),
            tooltip: 'Search',
            onPressed: () {
              setState(() {
                _isSearching = true;
                _isEditing = false;
              });
            },
            visualDensity: VisualDensity.compact,
          ),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: l10n.actionRefresh,
            onPressed: () {
              ref.read(panelControllerProvider.notifier).refresh(widget.side);
            },
            visualDensity: VisualDensity.compact,
          ),
          // Hidden files toggle
          IconButton(
            icon: Icon(
              state.activeTab.showHidden
                  ? Icons.visibility
                  : Icons.visibility_off,
              size: 18,
            ),
            tooltip: state.activeTab.showHidden
                ? 'Gizli dosyaları gizle'
                : 'Gizli dosyaları göster',
            onPressed: () {
              _panels.toggleHidden(widget.side);
            },
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
