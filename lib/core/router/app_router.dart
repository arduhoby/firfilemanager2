import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/shell_adaptive/shell_adaptive.dart';
import '../../features/server_mode/server_mode_page.dart';
import '../../features/file_operations/sync_jobs_page.dart';

part 'app_router.g.dart';

/// Application router configuration using go_router.
///
/// Uses a [ShellRoute] to wrap all routes with the adaptive shell (dual-pane
/// or category shell depending on screen size). This keeps the navigation
/// chrome persistent while the inner content changes.
@Riverpod(keepAlive: true)
GoRouter appRouter(AppRouterRef ref) {
  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    routes: [
      ShellRoute(
        builder: (context, state, child) => ShellAdaptive(child: child),
        routes: [
          GoRoute(
            path: '/',
            name: 'home',
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/connections',
            name: 'connections',
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/connections/new',
            name: 'connectionNew',
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/server',
            name: 'server',
            builder: (context, state) => const ServerModePage(),
          ),
          GoRoute(
            path: '/sync',
            name: 'syncJobs',
            builder: (context, state) => const SyncJobsPage(),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) => const SizedBox.shrink(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) =>
        Scaffold(body: Center(child: Text('Page not found: ${state.error}'))),
  );
}
