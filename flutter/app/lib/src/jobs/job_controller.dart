import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State of the currently running user-visible job (one at a time for now).
class JobState {
  const JobState({
    required this.label,
    this.percent = 0,
    this.message = '',
    this.running = true,
    this.cancelled = false,
    this.startedAt,
    this.log = const <String>[],
  });

  final String label;
  final int percent;
  final String message;
  final bool running;
  final bool cancelled;
  final DateTime? startedAt;
  final List<String> log;

  Duration get elapsed =>
      startedAt == null ? Duration.zero : DateTime.now().difference(startedAt!);

  JobState copyWith({
    int? percent,
    String? message,
    bool? running,
    bool? cancelled,
    DateTime? startedAt,
    List<String>? log,
  }) => JobState(
    label: label,
    percent: percent ?? this.percent,
    message: message ?? this.message,
    running: running ?? this.running,
    cancelled: cancelled ?? this.cancelled,
    startedAt: startedAt ?? this.startedAt,
    log: log ?? this.log,
  );
}

/// Tracks a single background operation: label, progress, message, a rolling
/// log and a cooperative cancellation flag polled by the running service.
class JobController extends Notifier<JobState?> {
  bool _cancelRequested = false;

  @override
  JobState? build() => null;

  bool get cancelRequested => _cancelRequested;

  void start(String label, {String message = 'Starting...'}) {
    _cancelRequested = false;
    state = JobState(
      label: label,
      message: message,
      startedAt: DateTime.now(),
      log: <String>['$label: $message'],
    );
  }

  void progress(int percent, String message) {
    final current = state;
    if (current == null) return;
    final log = <String>[...current.log, message];
    if (log.length > 200) log.removeRange(0, log.length - 200);
    state = current.copyWith(
      percent: percent.clamp(0, 100),
      message: message,
      log: log,
    );
  }

  void requestCancel({
    String message = 'Cancelling...',
    String logEntry = 'Cancellation requested',
  }) {
    _cancelRequested = true;
    final current = state;
    if (current != null) {
      state = current.copyWith(
        cancelled: true,
        message: message,
        log: <String>[...current.log, logEntry],
      );
    }
  }

  void finish() {
    state = null;
    _cancelRequested = false;
  }
}

final jobProvider = NotifierProvider<JobController, JobState?>(
  JobController.new,
);
