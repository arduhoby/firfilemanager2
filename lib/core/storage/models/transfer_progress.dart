import 'dart:collection';

import 'file_entry.dart';

/// A token that can be used to cancel an ongoing transfer operation.
///
/// Pass it to [StorageProvider.read], [StorageProvider.write], or
/// [StorageProvider.copy] and call [cancel] to abort the operation.
class CancelToken {
  CancelToken();

  bool _isCancelled = false;
  final List<void Function()> _callbacks = [];

  /// Whether cancellation has been requested
  bool get isCancelled => _isCancelled;

  /// Request cancellation of the associated operation
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final callback in _callbacks) {
      callback();
    }
  }

  /// Register a callback to be called when [cancel] is invoked
  void onCancel(void Function() callback) {
    if (_isCancelled) {
      callback();
    } else {
      _callbacks.add(callback);
    }
  }

  /// Reset the token for reuse
  void reset() {
    _isCancelled = false;
    _callbacks.clear();
  }
}

/// Type of transfer operation
enum TransferOperation { copy, move, delete, read, write, zip, unzip, sync }

/// State of a transfer operation
enum TransferState {
  /// Operation is queued but not started
  pending,

  /// Operation is in progress
  inProgress,

  /// Operation completed successfully
  completed,

  /// Operation was cancelled by the user
  cancelled,

  /// Operation failed with an error
  failed,
}

/// Progress update for a file transfer operation.
///
/// Emitted as a [Stream] by [StorageProvider.read], [StorageProvider.write],
/// and [StorageProvider.copy]. The stream emits progress updates during the
/// operation and a final update with [state] set to [TransferState.completed]
/// or [TransferState.failed].
class TransferProgress {
  TransferProgress({
    required this.operation,
    required this.state,
    this.currentFile,
    this.bytesTransferred = 0,
    this.totalBytes = 0,
    this.filesTransferred = 0,
    this.totalFiles = 0,
    this.speed = 0,
    this.overallBytesTransferred = 0,
    this.overallTotalBytes = 0,
    this.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Type of operation
  final TransferOperation operation;

  /// Current state
  final TransferState state;

  /// The file currently being transferred
  final FileEntry? currentFile;

  /// Bytes transferred so far for the current file
  final int bytesTransferred;

  /// Total bytes for the current file (0 if unknown)
  final int totalBytes;

  /// Number of files transferred so far (for batch operations)
  final int filesTransferred;

  /// Total number of files in the batch (0 if single file)
  final int totalFiles;

  /// Bytes transferred across the complete batch.
  final int overallBytesTransferred;

  /// Total bytes across the complete batch (0 if unknown).
  final int overallTotalBytes;

  /// Transfer speed in bytes/second
  final double speed;

  /// Error message if [state] is [TransferState.failed]
  final String? error;

  /// When this progress update was created
  final DateTime timestamp;

  /// Current-file progress as a fraction, or null when its size is unknown.
  double? get currentFileFraction {
    if (totalBytes <= 0) return null;
    return (bytesTransferred / totalBytes).clamp(0, 1).toDouble();
  }

  /// Complete-batch progress as a fraction, or null when its size is unknown.
  double? get overallFraction {
    if (overallTotalBytes <= 0) return null;
    return (overallBytesTransferred / overallTotalBytes).clamp(0, 1).toDouble();
  }

  /// File-count progress, used when byte totals are unavailable.
  double? get fileFraction {
    if (totalFiles <= 0) return null;
    return (filesTransferred / totalFiles).clamp(0, 1).toDouble();
  }

  /// Primary progress, preferring complete-batch bytes.
  double? get fraction =>
      overallFraction ?? currentFileFraction ?? fileFraction;

  /// Progress as a percentage (0 to 100), or null if total is unknown.
  int? get percent {
    final f = fraction;
    return f == null ? null : (f * 100).round();
  }

  int get currentFileRemainingBytes =>
      (totalBytes - bytesTransferred).clamp(0, totalBytes).toInt();

  int get overallRemainingBytes => (overallTotalBytes - overallBytesTransferred)
      .clamp(0, overallTotalBytes)
      .toInt();

  /// ETA based on the current rolling transfer speed.
  Duration? get estimatedRemaining {
    if (speed <= 0 || overallRemainingBytes <= 0) return null;
    return Duration(seconds: (overallRemainingBytes / speed).ceil());
  }

  /// Whether the operation is finished (completed, cancelled, or failed)
  bool get isFinished =>
      state == TransferState.completed ||
      state == TransferState.cancelled ||
      state == TransferState.failed;

  TransferProgress copyWith({
    TransferOperation? operation,
    TransferState? state,
    FileEntry? currentFile,
    int? bytesTransferred,
    int? totalBytes,
    int? filesTransferred,
    int? totalFiles,
    int? overallBytesTransferred,
    int? overallTotalBytes,
    double? speed,
    String? error,
  }) {
    return TransferProgress(
      operation: operation ?? this.operation,
      state: state ?? this.state,
      currentFile: currentFile ?? this.currentFile,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      totalBytes: totalBytes ?? this.totalBytes,
      filesTransferred: filesTransferred ?? this.filesTransferred,
      totalFiles: totalFiles ?? this.totalFiles,
      overallBytesTransferred:
          overallBytesTransferred ?? this.overallBytesTransferred,
      overallTotalBytes: overallTotalBytes ?? this.overallTotalBytes,
      speed: speed ?? this.speed,
      error: error ?? this.error,
    );
  }

  @override
  String toString() =>
      'TransferProgress(op: $operation, state: $state, '
      'current: $bytesTransferred/$totalBytes bytes, '
      'overall: $overallBytesTransferred/$overallTotalBytes bytes, '
      '$filesTransferred/$totalFiles files, ${percent ?? '?'}%)';
}

/// Rolling byte-rate estimator used for stable speed and ETA values.
class TransferRateTracker {
  TransferRateTracker({
    this.window = const Duration(seconds: 4),
    this.minimumSampleDuration = const Duration(milliseconds: 400),
    this.smoothingFactor = 0.2,
  }) : assert(smoothingFactor > 0 && smoothingFactor <= 1);

  final Duration window;
  final Duration minimumSampleDuration;
  final double smoothingFactor;
  final Queue<_TransferSample> _samples = Queue<_TransferSample>();
  double _smoothedSpeed = 0;

  double addSample(int bytesTransferred, {DateTime? timestamp}) {
    final now = timestamp ?? DateTime.now();
    if (_samples.isNotEmpty &&
        bytesTransferred < _samples.last.bytesTransferred) {
      reset();
    }
    _samples.add(
      _TransferSample(timestamp: now, bytesTransferred: bytesTransferred),
    );

    final cutoff = now.subtract(window);
    while (_samples.length > 2 &&
        _samples.elementAt(1).timestamp.isBefore(cutoff)) {
      _samples.removeFirst();
    }

    if (_samples.length < 2) return _smoothedSpeed;
    final first = _samples.first;
    final elapsed = now.difference(first.timestamp);
    final transferred = bytesTransferred - first.bytesTransferred;
    if (elapsed < minimumSampleDuration || transferred <= 0) {
      return _smoothedSpeed;
    }

    final rawSpeed =
        transferred * Duration.microsecondsPerSecond / elapsed.inMicroseconds;
    _smoothedSpeed = _smoothedSpeed == 0
        ? rawSpeed
        : _smoothedSpeed + smoothingFactor * (rawSpeed - _smoothedSpeed);
    return _smoothedSpeed;
  }

  void reset() {
    _samples.clear();
    _smoothedSpeed = 0;
  }
}

class _TransferSample {
  const _TransferSample({
    required this.timestamp,
    required this.bytesTransferred,
  });

  final DateTime timestamp;
  final int bytesTransferred;
}
