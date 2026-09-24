import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State of the currently running user-visible job (one at a time for now).
class JobState {
  const JobState({
    required this.label,
    this.percent = 0,
    this.message = '',
    this.running = true,
    this.cancelled = false,
  });

  final String label;
  final int percent;
  final String message;
  final bool running;
  final bool cancelled;

  JobState copyWith({
    int? percent,
    String? message,
    bool? running,
    bool? cancelled,
  }) =>
      JobState(
        label: label,
        percent: percent ?? this.percent,
        message: message ?? this.message,
        running: running ?? this.running,
        cancelled: cancelled ?? this.cancelled,
      );
}

/// Tracks a single background operation: label, progress, message and a
/// cooperative cancellation flag polled by the running service.
class JobController extends Notifier<JobState?> {
  bool _cancelRequested = false;

  @override
  JobState? build() => null;

  bool get cancelRequested => _cancelRequested;

  void start(String label, {String message = 'Starting...'}) {
    _cancelRequested = false;
    state = JobState(label: label, message: message);
  }

  void progress(int percent, String message) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(percent: percent.clamp(0, 100), message: message);
  }

  void requestCancel() {
    _cancelRequested = true;
    final current = state;
    if (current != null) {
      state = current.copyWith(cancelled: true, message: 'Cancelling...');
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
