import 'package:fir_file_manager/features/file_operations/file_operations_state.dart';
import 'package:fir_file_manager/features/shell_adaptive/panel_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const third = PanelId('panel-3');
  const fourth = PanelId('panel-4');
  const fifth = PanelId('panel-5');

  test('keeps two and three panels in a single row', () {
    expect(PanelLayoutSpec.forPanels([PanelId.a, PanelId.b]).rows, [
      [PanelId.a, PanelId.b],
    ]);
    expect(PanelLayoutSpec.forPanels([PanelId.a, PanelId.b, third]).rows, [
      [PanelId.a, PanelId.b, third],
    ]);
  });

  test('lays out four panels as a two by two grid', () {
    expect(
      PanelLayoutSpec.forPanels([PanelId.a, PanelId.b, third, fourth]).rows,
      [
        [PanelId.a, PanelId.b],
        [third, fourth],
      ],
    );
  });

  test('lays out five panels as three above and two below', () {
    expect(
      PanelLayoutSpec.forPanels([
        PanelId.a,
        PanelId.b,
        third,
        fourth,
        fifth,
      ]).rows,
      [
        [PanelId.a, PanelId.b, third],
        [fourth, fifth],
      ],
    );
  });
}
