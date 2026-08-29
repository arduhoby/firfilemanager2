import 'package:fir_file_manager/core/storage/models/file_entry.dart';
import 'package:fir_file_manager/features/file_operations/sync_models.dart';
import 'package:fir_file_manager/features/shell_adaptive/sync_preview_dialog.dart';
import 'package:fir_file_manager/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('supports sorting, clearing, and custom sync selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final modified = DateTime.utc(2026, 1, 1, 12);
    final different = FileEntry(
      name: 'different.bin',
      path: '/source/different.bin',
      isDirectory: false,
      size: 300,
      modified: modified,
    );
    final equal = FileEntry(
      name: 'equal.bin',
      path: '/source/equal.bin',
      isDirectory: false,
      size: 100,
      modified: modified,
    );
    final missing = FileEntry(
      name: 'missing.bin',
      path: '/source/missing.bin',
      isDirectory: false,
      size: 200,
      modified: modified,
    );
    List<SyncItem>? selected;
    SyncPreviewSelection? saved;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  selected = await showDialog<List<SyncItem>>(
                    context: context,
                    builder: (context) => SyncPreviewDialog(
                      sourcePath: '/source',
                      destPath: '/destination',
                      items: [
                        SyncItem(
                          sourceEntry: different,
                          destinationEntry: different.copyWith(
                            path: '/destination/different.bin',
                          ),
                          relativePath: different.name,
                          depth: 0,
                          status: SyncStatus.modified,
                          isSelected: true,
                        ),
                        SyncItem(
                          sourceEntry: equal,
                          destinationEntry: equal.copyWith(
                            path: '/destination/equal.bin',
                          ),
                          relativePath: equal.name,
                          depth: 0,
                          status: SyncStatus.identical,
                          isSelected: false,
                        ),
                        SyncItem(
                          sourceEntry: missing,
                          relativePath: missing.name,
                          depth: 0,
                          status: SyncStatus.missing,
                          isSelected: true,
                        ),
                      ],
                      onSave: (selection) async => saved = selection,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('2 of 3 files selected'), findsOneWidget);
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey('sync-select-status-missing')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey('sync-select-status-modified')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey('sync-select-status-identical')),
          )
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey('sync-select-all-toolbar')),
          )
          .value,
      isNull,
    );
    expect(
      tester
          .widgetList<Text>(find.text('different.bin'))
          .every((text) => text.style?.color == Colors.blue.shade700),
      isTrue,
    );
    expect(
      tester.widget<Text>(find.text('missing.bin')).style?.color,
      Colors.red.shade700,
    );
    expect(
      tester
          .widgetList<Text>(find.text('equal.bin'))
          .every((text) => text.style?.color == Colors.green.shade700),
      isTrue,
    );
    expect(
      tester
          .getCenter(find.byKey(const ValueKey('sync-select-different.bin')))
          .dy,
      lessThan(
        tester
            .getCenter(find.byKey(const ValueKey('sync-select-equal.bin')))
            .dy,
      ),
    );

    await tester.tap(find.text('Size').first);
    await tester.pumpAndSettle();

    expect(
      tester.getCenter(find.byKey(const ValueKey('sync-select-equal.bin'))).dy,
      lessThan(
        tester
            .getCenter(find.byKey(const ValueKey('sync-select-missing.bin')))
            .dy,
      ),
    );
    expect(
      tester
          .getCenter(find.byKey(const ValueKey('sync-select-missing.bin')))
          .dy,
      lessThan(
        tester
            .getCenter(find.byKey(const ValueKey('sync-select-different.bin')))
            .dy,
      ),
    );

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(find.text('0 of 3 files selected'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sync-select-equal.bin')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 3 files selected'), findsOneWidget);
    await tester.tap(find.text('Save task…'));
    await tester.pumpAndSettle();
    expect(saved?.selectedItems.single.relativePath, 'equal.bin');
    expect(saved?.policy.identical, isFalse);
    expect(saved?.includedPaths, {'equal.bin'});

    await tester.tap(find.text('Synchronize (1)'));
    await tester.pumpAndSettle();

    expect(selected, hasLength(1));
    expect(selected?.single.sourceEntry.name, 'equal.bin');
    expect(selected?.single.status, SyncStatus.identical);
  });

  testWidgets('uses the adaptive card view on a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final entry = FileEntry(
      name: 'mobile.txt',
      path: '/source/mobile.txt',
      isDirectory: false,
      size: 12,
      modified: DateTime.utc(2026, 8, 10),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showDialog<List<SyncItem>>(
                  context: context,
                  builder: (context) => SyncPreviewDialog(
                    sourcePath: '/source',
                    destPath: '/destination',
                    items: [
                      SyncItem(
                        sourceEntry: entry,
                        destinationEntry: entry.copyWith(
                          path: '/destination/mobile.txt',
                        ),
                        relativePath: 'mobile.txt',
                        depth: 0,
                        status: SyncStatus.modified,
                        isSelected: true,
                        comparisonReason: 'Size',
                      ),
                    ],
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(DataTable), findsNothing);
    expect(
      find.byKey(const ValueKey('sync-card-select-mobile.txt')),
      findsOneWidget,
    );
    expect(find.text('mobile.txt'), findsNWidgets(2));
    expect(find.text('Size'), findsAtLeastNWidgets(1));
    expect(find.text('1 of 1 files selected'), findsOneWidget);
  });
}
