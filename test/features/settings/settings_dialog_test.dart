import 'package:fir_file_manager/features/settings/settings_dialog.dart';
import 'package:fir_file_manager/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  testWidgets('shows the installed application version in settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          packageInfoProvider.overrideWith(
            (ref) async => PackageInfo(
              appName: 'Fir File Manager',
              packageName: 'fir_file_manager',
              version: '1.0.2',
              buildNumber: '2',
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SettingsDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sürüm'), findsOneWidget);
    expect(find.text('1.0.2 (2)'), findsOneWidget);
  });
}
