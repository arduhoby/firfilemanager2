import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../file_operations/file_operations_state.dart';

class PanelTabsBar extends ConsumerWidget {
  const PanelTabsBar({super.key, required this.side});

  final PanelId side;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final panelState = ref.watch(panelStateProvider(side));
    final panels = ref.read(panelWorkspaceProvider.notifier);

    final tabs = panelState.tabs;
    final activeIndex = panelState.activeTabIndex;

    if (tabs.length <= 1) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x22FFFFFF) : const Color(0x0A000000),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0x10FFFFFF) : const Color(0x08000000),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final isActive = index == activeIndex;

                return Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        panels.setActiveTab(side, index);
                      },
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 160),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: isActive
                              ? (isDark
                                    ? const Color(0xFF38383A)
                                    : const Color(0xFFFFFFFF))
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: isActive
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 2,
                                    offset: const Offset(0, 1),
                                  ),
                                ]
                              : null,
                          border: isActive
                              ? Border.all(
                                  color: isDark
                                      ? const Color(0x33FFFFFF)
                                      : const Color(0x11000000),
                                  width: 0.5,
                                )
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                tab.currentPath == '/'
                                    ? 'Root'
                                    : tab.currentPath.split('/').last,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontSize: 11,
                                  fontWeight: isActive
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                                  color: isActive
                                      ? theme.colorScheme.onSurface
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onHover: (hovering) {
                                // optional: change icon color on hover
                              },
                              onTap: () {
                                panels.closeTab(side, index);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  Icons.close,
                                  size: 12,
                                  color: isActive
                                      ? theme.colorScheme.onSurfaceVariant
                                      : theme.colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () {
                panels.addTab(side, '/');
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.add, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
