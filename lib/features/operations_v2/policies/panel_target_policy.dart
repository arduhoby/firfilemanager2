class PanelTargetCandidate {
  const PanelTargetCandidate({required this.panelId, required this.isWritable});

  final String panelId;
  final bool isWritable;
}

enum PanelTargetDecisionType { unavailable, direct, selectionRequired }

class PanelTargetDecision {
  const PanelTargetDecision._({
    required this.type,
    required this.candidates,
    this.directPanelId,
  });

  const PanelTargetDecision.unavailable()
    : this._(
        type: PanelTargetDecisionType.unavailable,
        candidates: const <String>[],
      );

  const PanelTargetDecision.direct(String panelId)
    : this._(
        type: PanelTargetDecisionType.direct,
        candidates: const <String>[],
        directPanelId: panelId,
      );

  const PanelTargetDecision.selectionRequired(List<String> candidates)
    : this._(
        type: PanelTargetDecisionType.selectionRequired,
        candidates: candidates,
      );

  final PanelTargetDecisionType type;
  final List<String> candidates;
  final String? directPanelId;
}

class PanelTargetPolicy {
  const PanelTargetPolicy();

  PanelTargetDecision resolve({
    required String sourcePanelId,
    required Iterable<PanelTargetCandidate> candidates,
  }) {
    final valid =
        candidates
            .where(
              (candidate) =>
                  candidate.panelId != sourcePanelId && candidate.isWritable,
            )
            .map((candidate) => candidate.panelId)
            .toSet()
            .toList(growable: false)
          ..sort();
    if (valid.isEmpty) return const PanelTargetDecision.unavailable();
    if (valid.length == 1) return PanelTargetDecision.direct(valid.single);
    return PanelTargetDecision.selectionRequired(
      List<String>.unmodifiable(valid),
    );
  }
}
