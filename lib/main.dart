import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/generated/app_localizations.dart';
import 'core/router/app_router.dart';
import 'core/settings/settings_provider.dart';
import 'core/theme/app_theme.dart';
import 'features/file_operations/sync_job_models.dart';
import 'features/file_operations/sync_job_runner.dart';

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();

  final jobIdIndex = arguments.indexOf('--run-sync-id');
  final jobNameIndex = arguments.indexOf('--run-sync');
  if (jobIdIndex >= 0 || jobNameIndex >= 0) {
    final container = ProviderContainer();
    try {
      final runner = container.read(syncJobRunnerProvider.notifier);
      final report = jobIdIndex >= 0
          ? await runner.runById(
              arguments[jobIdIndex + 1],
              trigger: SyncRunTrigger.commandLine,
            )
          : await runner.runByName(
              arguments[jobNameIndex + 1],
              trigger: SyncRunTrigger.commandLine,
            );
      exit(report.outcome == SyncRunOutcome.success ? 0 : 1);
    } catch (error) {
      stderr.writeln(error);
      exit(1);
    } finally {
      container.dispose();
    }
  }

  if (Platform.isAndroid || Platform.isIOS) {
    await Permission.storage.request();
    if (Platform.isAndroid) {
      await Permission.manageExternalStorage.request();
      await Permission.notification.request();
    }
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
  }

  runApp(const ProviderScope(child: FirFileManagerApp()));
}

@pragma('vm:entry-point')
Future<void> smartSyncBackgroundMain(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (arguments.isEmpty) {
    throw StateError('A synchronization job ID is required.');
  }
  final container = ProviderContainer();
  var succeeded = false;
  try {
    final report = await container
        .read(syncJobRunnerProvider.notifier)
        .runById(arguments.first, trigger: SyncRunTrigger.scheduled);
    succeeded = report.outcome == SyncRunOutcome.success;
  } finally {
    try {
      await const MethodChannel(
        'fir_file_manager/sync_background',
      ).invokeMethod<void>('complete', {'succeeded': succeeded});
    } finally {
      container.dispose();
    }
  }
}

/// Root widget for the Fir File Manager application.
class FirFileManagerApp extends ConsumerWidget {
  const FirFileManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Fir File Manager',
      debugShowCheckedModeBanner: false,

      // Theme
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings.flutterThemeMode,

      // Localization
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // Router
      routerConfig: router,
    );
  }
}
