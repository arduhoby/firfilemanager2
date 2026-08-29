import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FilePanel no longer owns string-based context-menu dispatch', () async {
    final source = await File(
      'lib/features/shell_adaptive/file_panel.dart',
    ).readAsString();

    expect(source, isNot(contains('switch (value)')));
    expect(source, contains('CommandOrchestrator'));
    expect(source, contains('FilePanelContextMenuBuilder'));
  });
}
