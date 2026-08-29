import 'package:fir_file_manager/core/storage/models/transfer_progress.dart';
import 'package:fir_file_manager/features/file_operations/operation_completion_sound_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TransferProgress progress({
    required TransferOperation operation,
    required TransferState state,
    int filesTransferred = 0,
    int totalFiles = 0,
  }) => TransferProgress(
    operation: operation,
    state: state,
    filesTransferred: filesTransferred,
    totalFiles: totalFiles,
  );

  test('plays once for completed copy, move, and sync operations', () {
    for (final operation in [
      TransferOperation.copy,
      TransferOperation.move,
      TransferOperation.zip,
      TransferOperation.sync,
    ]) {
      expect(
        OperationCompletionSoundPolicy.shouldPlay(
          enabled: true,
          previous: progress(
            operation: operation,
            state: TransferState.inProgress,
            filesTransferred: 1,
            totalFiles: 2,
          ),
          next: progress(
            operation: operation,
            state: TransferState.completed,
            filesTransferred: 2,
            totalFiles: 2,
          ),
        ),
        isTrue,
      );
    }
  });

  test('rejects intermediate, repeated, empty, and disabled completion', () {
    final completed = progress(
      operation: TransferOperation.sync,
      state: TransferState.completed,
      filesTransferred: 2,
      totalFiles: 2,
    );

    expect(
      OperationCompletionSoundPolicy.shouldPlay(
        enabled: false,
        previous: null,
        next: completed,
      ),
      isFalse,
    );
    expect(
      OperationCompletionSoundPolicy.shouldPlay(
        enabled: true,
        previous: completed,
        next: completed,
      ),
      isFalse,
    );
    expect(
      OperationCompletionSoundPolicy.shouldPlay(
        enabled: true,
        previous: null,
        next: progress(
          operation: TransferOperation.copy,
          state: TransferState.completed,
        ),
      ),
      isFalse,
    );
    expect(
      OperationCompletionSoundPolicy.shouldPlay(
        enabled: true,
        previous: null,
        next: progress(
          operation: TransferOperation.move,
          state: TransferState.completed,
          filesTransferred: 1,
          totalFiles: 2,
        ),
      ),
      isFalse,
    );
  });
}
