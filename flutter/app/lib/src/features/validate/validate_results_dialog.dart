import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cbzmanager/l10n/generated/app_localizations.dart';

import '../../util/service_messages.dart';
import 'validate_service.dart';

/// Shows the aggregated validation outcome with a copyable report.
Future<void> showValidateResultsDialog(
  BuildContext context,
  List<ValidateOutcome> outcomes,
) {
  final valid = outcomes.where((o) => o.result.valid).length;
  final failed = outcomes.length - valid;

  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final l10n = AppLocalizations.of(context);
      return AlertDialog(
        title: Text(l10n.validationResults),
        content: SizedBox(
          width: 520,
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(Icons.check_circle, size: 18),
                    label: Text(l10n.validCount(valid)),
                  ),
                  if (failed > 0)
                    Chip(
                      avatar: const Icon(Icons.error, size: 18),
                      label: Text(l10n.failedWithErrors(failed)),
                      backgroundColor: theme.colorScheme.errorContainer,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: outcomes.every((o) => o.result.valid)
                    ? Center(child: Text(l10n.allArchivesValid))
                    : ListView.builder(
                        itemCount: outcomes.length,
                        itemBuilder: (context, index) {
                          final outcome = outcomes[index];
                          if (outcome.result.valid) {
                            return ListTile(
                              dense: true,
                              leading: const Icon(
                                Icons.check,
                                color: Colors.green,
                              ),
                              title: Text(outcome.item.name),
                            );
                          }
                          return ExpansionTile(
                            leading: Icon(
                              Icons.error_outline,
                              color: theme.colorScheme.error,
                            ),
                            title: Text(outcome.item.name),
                            subtitle: Text(
                              outcome.result.error != null
                                  ? localizeServiceMessage(
                                      l10n,
                                      outcome.result.error!,
                                    )
                                  : l10n.pageErrors(
                                      outcome.result.errors.length,
                                    ),
                            ),
                            children: [
                              for (final error in outcome.result.errors)
                                ListTile(
                                  dense: true,
                                  title: Text(error.page),
                                  subtitle: Text(
                                    localizeServiceMessage(l10n, error.message),
                                  ),
                                ),
                              if (outcome.result.errors.isEmpty &&
                                  outcome.result.error != null)
                                ListTile(
                                  dense: true,
                                  subtitle: Text(
                                    localizeServiceMessage(
                                      l10n,
                                      outcome.result.error!,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: _report(l10n, outcomes))),
            icon: const Icon(Icons.copy),
            label: Text(l10n.copyReport),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.close),
          ),
        ],
      );
    },
  );
}

String _report(AppLocalizations l10n, List<ValidateOutcome> outcomes) {
  final valid = outcomes.where((o) => o.result.valid).length;
  final buffer = StringBuffer()
    ..writeln(
      l10n.reportHeader(outcomes.length, valid, outcomes.length - valid),
    );
  for (final outcome in outcomes) {
    buffer.writeln(
      '${outcome.result.valid ? 'OK  ' : 'FAIL'} ${outcome.item.name}'
      '${outcome.result.imageCount > 0 ? ' (${outcome.result.imageCount} images)' : ''}',
    );
    if (!outcome.result.valid) {
      if (outcome.result.error != null) {
        buffer.writeln(
          '     ${localizeServiceMessage(l10n, outcome.result.error!)}',
        );
      }
      for (final error in outcome.result.errors) {
        buffer.writeln('     ${error.page}: ${error.message}');
      }
    }
  }
  return buffer.toString();
}
