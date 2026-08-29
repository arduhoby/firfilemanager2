import 'package:fir_file_manager/features/connections/connection_dialog.dart';
import 'package:fir_file_manager/features/connections/connections_sidebar.dart';
import 'package:fir_file_manager/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => ProviderScope(
  child: MaterialApp(
    locale: const Locale('tr'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('sidebar renders a hierarchical network tree', (tester) async {
    await tester.pumpWidget(_app(const ConnectionsSidebar()));
    await tester.pump();

    expect(find.text('Network'), findsOneWidget);
    expect(find.text('Kayıtlı Bağlantılar'), findsOneWidget);
    expect(find.text('Ağda Bulunanlar'), findsOneWidget);
  });

  testWidgets('connection form changes fields for the selected protocol', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const ConnectionDialog()));
    await tester.pump();

    expect(find.text('SFTP'), findsOneWidget);
    expect(find.text('Sunucu'), findsOneWidget);

    await tester.tap(find.text('OneDrive'));
    await tester.pump();

    expect(find.text('Sunucu'), findsNothing);
    expect(
      find.text(
        'Yetkilendirme işlemi tarayıcınızda açılacak web sayfası üzerinden gerçekleştirilecektir.',
      ),
      findsOneWidget,
    );
  });
}
