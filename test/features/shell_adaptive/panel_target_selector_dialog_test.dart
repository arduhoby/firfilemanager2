import 'package:fir_file_manager/features/file_operations/file_operations_state.dart';
import 'package:fir_file_manager/features/file_operations/panel_target_selection.dart';
import 'package:fir_file_manager/features/shell_adaptive/panel_target_selector_dialog.dart';
import 'package:fir_file_manager/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const third = PanelId('panel-3');
  const fourth = PanelId('panel-4');
  const fifth = PanelId('panel-5');
  const catalog = PanelTargetCatalog(
    source: PanelTargetDescriptor(
      panelId: PanelId.a,
      panelNumber: 1,
      providerId: 'local',
      providerDisplayName: 'Local',
      path: '/source',
    ),
    targets: [
      PanelTargetDescriptor(
        panelId: PanelId.b,
        panelNumber: 2,
        providerId: 'local',
        providerDisplayName: 'Local',
        path: '/destination',
      ),
      PanelTargetDescriptor(
        panelId: third,
        panelNumber: 3,
        providerId: 'local',
        providerDisplayName: 'Local',
        path: '/source',
        blockReason: PanelTargetBlockReason.sameEndpoint,
      ),
      PanelTargetDescriptor(
        panelId: fourth,
        panelNumber: 4,
        providerId: 'sftp',
        providerDisplayName: 'Server',
        path: '/backup',
      ),
      PanelTargetDescriptor(
        panelId: fifth,
        panelNumber: 5,
        providerId: 'sftp',
        providerDisplayName: 'Server',
        path: '/archive',
        blockReason: PanelTargetBlockReason.unsupportedDestination,
      ),
    ],
  );

  Future<void> pumpDialog(
    WidgetTester tester, {
    required PanelTargetOperation operation,
    required bool allowMultiple,
    required ValueChanged<List<PanelId>?> onSelected,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async => onSelected(
                await showDialog<List<PanelId>>(
                  context: context,
                  builder: (context) => PanelTargetSelectorDialog(
                    catalog: catalog,
                    operation: operation,
                    allowMultiple: allowMultiple,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'copy mode selects every valid target and preserves panel order',
    (tester) async {
      List<PanelId>? selected;
      await pumpDialog(
        tester,
        operation: PanelTargetOperation.copy,
        allowMultiple: true,
        onSelected: (value) => selected = value,
      );

      await tester.tap(find.byKey(const ValueKey('target-select-all')));
      await tester.pump();

      expect(find.text('2 of 2 selected'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('target-confirm')));
      await tester.pumpAndSettle();

      expect(selected, [PanelId.b, fourth]);
    },
  );

  testWidgets('sync mode reuses the selector with single-target behavior', (
    tester,
  ) async {
    List<PanelId>? selected;
    await pumpDialog(
      tester,
      operation: PanelTargetOperation.sync,
      allowMultiple: false,
      onSelected: (value) => selected = value,
    );

    await tester.tap(find.byKey(const ValueKey('target-panel-panel-b')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('target-panel-panel-4')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('target-confirm')));
    await tester.pumpAndSettle();

    expect(selected, [fourth]);
  });

  testWidgets('sync mode can select multiple target panels', (tester) async {
    List<PanelId>? selected;
    await pumpDialog(
      tester,
      operation: PanelTargetOperation.sync,
      allowMultiple: true,
      onSelected: (value) => selected = value,
    );

    await tester.tap(find.byKey(const ValueKey('target-select-all')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('target-confirm')));
    await tester.pumpAndSettle();

    expect(selected, [PanelId.b, fourth]);
  });

  testWidgets('compress mode reuses the multi-target selector', (tester) async {
    List<PanelId>? selected;
    await pumpDialog(
      tester,
      operation: PanelTargetOperation.compress,
      allowMultiple: true,
      onSelected: (value) => selected = value,
    );

    expect(find.text('Compress · Target panels'), findsOneWidget);
    expect(
      find.text('Select a local destination panel for compression'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('target-select-all')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('target-confirm')));
    await tester.pumpAndSettle();

    expect(selected, [PanelId.b, fourth]);
  });

  testWidgets('blocked targets cannot be selected', (tester) async {
    await pumpDialog(
      tester,
      operation: PanelTargetOperation.move,
      allowMultiple: true,
      onSelected: (_) {},
    );

    final blockedCheckbox = tester.widget<CheckboxListTile>(
      find.byKey(const ValueKey('target-panel-panel-3')),
    );
    expect(blockedCheckbox.onChanged, isNull);
    expect(find.text('Same location as the source panel'), findsOneWidget);
  });
}
