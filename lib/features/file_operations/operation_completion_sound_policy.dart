import '../../core/storage/models/transfer_progress.dart';

/// Canonical decision for the single operation-completion sound.
class OperationCompletionSoundPolicy {
  const OperationCompletionSoundPolicy._();

  static bool shouldPlay({
    required bool enabled,
    required TransferProgress? previous,
    required TransferProgress? next,
  }) {
    if (!enabled || next == null) return false;
    final completedWholeOperation =
        next.state == TransferState.completed &&
        next.totalFiles > 0 &&
        next.filesTransferred >= next.totalFiles;
    return previous?.state != TransferState.completed &&
        completedWholeOperation;
  }
}
