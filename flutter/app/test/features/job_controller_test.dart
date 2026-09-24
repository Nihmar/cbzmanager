import 'package:cbzmanager/src/jobs/job_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tracks start, progress (clamped), cancel and finish', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final job = container.read(jobProvider.notifier);

    expect(container.read(jobProvider), isNull);

    job.start('Validate');
    expect(container.read(jobProvider)!.label, 'Validate');
    expect(container.read(jobProvider)!.running, isTrue);

    job.progress(50, 'half');
    expect(container.read(jobProvider)!.percent, 50);
    job.progress(250, 'clamped');
    expect(container.read(jobProvider)!.percent, 100);

    expect(job.cancelRequested, isFalse);
    job.requestCancel();
    expect(job.cancelRequested, isTrue);
    expect(container.read(jobProvider)!.cancelled, isTrue);

    job.finish();
    expect(container.read(jobProvider), isNull);
    expect(job.cancelRequested, isFalse);
  });
}
