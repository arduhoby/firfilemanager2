import 'dart:async';

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connections/connections_sidebar.dart';
import '../../l10n/generated/app_localizations.dart';
import '../file_operations/file_operations_state.dart';
import '../file_operations/sync_jobs_page.dart';
import 'file_panel.dart';

class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({super.key});

  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell> {
  int _currentIndex = 0;
  bool _isDualPaneLandscape = true; // Toggle for landscape dual pane

  @override
  void initState() {
    super.initState();
    // In mobile, we might want to sync active panel with bottom nav
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(panelWorkspaceProvider.notifier)
          .setActive(_currentIndex == 0 ? PanelId.a : PanelId.b);
    });
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
      ref
          .read(panelWorkspaceProvider.notifier)
          .setActive(index == 0 ? PanelId.a : PanelId.b);
    });
  }

  void _openSyncJobs() {
    unawaited(
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const SyncJobsPage())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.orientationOf(context);
    final isLandscape = orientation == Orientation.landscape;

    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    EdgeInsetsGeometry getPlatformPadding() {
      if (Platform.isIOS) {
        return const EdgeInsets.only(left: 3.0, bottom: 1.0);
      } else if (Platform.isAndroid) {
        return const EdgeInsets.only(bottom: 3.0);
      }
      return EdgeInsets.zero;
    }

    // If landscape and dual pane is enabled
    if (isLandscape && _isDualPaneLandscape) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Fir File Manager'),
          actions: [
            IconButton(
              icon: const Icon(Icons.sync_lock_outlined),
              tooltip: loc.syncJobsTitle,
              onPressed: _openSyncJobs,
            ),
            IconButton(
              icon: const Icon(Icons.hub_outlined),
              tooltip: 'Sunucular & Bağlantılar',
              onPressed: () {
                unawaited(
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => SizedBox(
                      height: MediaQuery.of(context).size.height * 0.75,
                      child: const ConnectionsSidebar(),
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.splitscreen),
              tooltip: 'Tek panele geç',
              onPressed: () {
                setState(() {
                  _isDualPaneLandscape = false;
                });
              },
            ),
          ],
        ),
        body: Padding(
          padding: getPlatformPadding(),
          child: Row(
            children: [
              const Expanded(child: FilePanel(side: PanelId.a)),
              Container(width: 1, color: theme.dividerColor),
              const Expanded(child: FilePanel(side: PanelId.b)),
            ],
          ),
        ),
      );
    }

    // Portrait or single pane landscape
    final activeSide = _currentIndex == 0 ? PanelId.a : PanelId.b;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fir File Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_lock_outlined),
            tooltip: loc.syncJobsTitle,
            onPressed: _openSyncJobs,
          ),
          IconButton(
            icon: const Icon(Icons.hub_outlined),
            tooltip: 'Sunucular & Bağlantılar',
            onPressed: () {
              unawaited(
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => SizedBox(
                    height: MediaQuery.of(context).size.height * 0.75,
                    child: const ConnectionsSidebar(),
                  ),
                ),
              );
            },
          ),
          if (isLandscape)
            IconButton(
              icon: const Icon(Icons.vertical_split),
              tooltip: 'Çift panele geç',
              onPressed: () {
                setState(() {
                  _isDualPaneLandscape = true;
                });
              },
            ),
        ],
      ),
      body: Padding(
        padding: getPlatformPadding(),
        child: FilePanel(side: activeSide),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_open),
            selectedIcon: Icon(Icons.folder),
            label: 'Panel A',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_copy_outlined),
            selectedIcon: Icon(Icons.folder_copy),
            label: 'Panel B',
          ),
        ],
      ),
    );
  }
}
