import 'package:fir_file_manager/features/operations_v2/policies/panel_target_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = PanelTargetPolicy();

  test('one valid target is selected without opening a dialog', () {
    final result = policy.resolve(
      sourcePanelId: 'panel-a',
      candidates: const <PanelTargetCandidate>[
        PanelTargetCandidate(panelId: 'panel-a', isWritable: true),
        PanelTargetCandidate(panelId: 'panel-b', isWritable: true),
      ],
    );

    expect(result.type, PanelTargetDecisionType.direct);
    expect(result.directPanelId, 'panel-b');
  });

  test('multiple valid targets require multi-selection', () {
    final result = policy.resolve(
      sourcePanelId: 'panel-a',
      candidates: const <PanelTargetCandidate>[
        PanelTargetCandidate(panelId: 'panel-b', isWritable: true),
        PanelTargetCandidate(panelId: 'panel-c', isWritable: true),
        PanelTargetCandidate(panelId: 'panel-d', isWritable: false),
      ],
    );

    expect(result.type, PanelTargetDecisionType.selectionRequired);
    expect(result.candidates, <String>['panel-b', 'panel-c']);
  });
}
