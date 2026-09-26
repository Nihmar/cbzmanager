import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cbzmanager/l10n/generated/app_localizations.dart';

import 'job_controller.dart';

/// Non-modal job monitor: label, progress, elapsed time and the rolling log.
Future<void> showJobMonitor(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _JobMonitor(),
  );
}

class _JobMonitor extends ConsumerWidget {
  const _JobMonitor();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(jobProvider);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return SizedBox(
      height: 420,
      child: job == null
          ? Center(child: Text(l10n.noJobRunning))
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          job.label,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Text('${job.elapsed.inSeconds}s'),
                    ],
                  ),
                  Text(job.message, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: job.percent <= 0 ? null : job.percent / 100.0,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.dividerColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(8),
                        itemCount: job.log.length,
                        itemBuilder: (context, index) {
                          final entry = job.log[job.log.length - 1 - index];
                          return Text(entry, style: theme.textTheme.bodySmall);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Spacer(),
                      TextButton(
                        onPressed: job.cancelled
                            ? null
                            : () => ref
                                  .read(jobProvider.notifier)
                                  .requestCancel(
                                    message: l10n.cancelling,
                                    logEntry: l10n.cancellationRequested,
                                  ),
                        child: Text(l10n.cancel),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(l10n.close),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
