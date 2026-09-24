import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      return AlertDialog(
        title: const Text('Validation results'),
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
                    label: Text('$valid valid'),
                  ),
                  if (failed > 0)
                    Chip(
                      avatar: const Icon(Icons.error, size: 18),
                      label: Text('$failed with errors'),
                      backgroundColor: theme.colorScheme.errorContainer,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: outcomes.every((o) => o.result.valid)
                    ? const Center(
                        child: Text('All archives are valid.'),
                      )
                    : ListView.builder(
                        itemCount: outcomes.length,
                        itemBuilder: (context, index) {
                          final outcome = outcomes[index];
                          if (outcome.result.valid) {
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.check, color: Colors.green),
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
                              outcome.result.error ??
                                  '${outcome.result.errors.length} page error(s)',
                            ),
                            children: [
                              for (final error in outcome.result.errors)
                                ListTile(
                                  dense: true,
                                  title: Text(error.page),
                                  subtitle: Text(error.message),
                                ),
                              if (outcome.result.errors.isEmpty &&
                                  outcome.result.error != null)
                                ListTile(
                                  dense: true,
                                  subtitle: Text(outcome.result.error!),
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
            onPressed: () => Clipboard.setData(
              ClipboardData(text: _report(outcomes)),
            ),
            icon: const Icon(Icons.copy),
            label: const Text('Copy report'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

String _report(List<ValidateOutcome> outcomes) {
  final valid = outcomes.where((o) => o.result.valid).length;
  final buffer = StringBuffer()
    ..writeln('Validation report — ${outcomes.length} file(s): '
        '$valid ok, ${outcomes.length - valid} failed');
  for (final outcome in outcomes) {
    buffer.writeln('${outcome.result.valid ? 'OK  ' : 'FAIL'} ${outcome.item.name}'
        '${outcome.result.imageCount > 0 ? ' (${outcome.result.imageCount} images)' : ''}');
    if (!outcome.result.valid) {
      if (outcome.result.error != null) {
        buffer.writeln('     ${outcome.result.error}');
      }
      for (final error in outcome.result.errors) {
        buffer.writeln('     ${error.page}: ${error.message}');
      }
    }
  }
  return buffer.toString();
}
