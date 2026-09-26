import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cbzmanager/l10n/generated/app_localizations.dart';

import 'settings.dart';

Future<void> showSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _SettingsDialog(),
  );
}

class _SettingsDialog extends ConsumerStatefulWidget {
  const _SettingsDialog();

  @override
  ConsumerState<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<_SettingsDialog> {
  late AppSettings _settings = ref.read(settingsProvider);
  late final _convert = TextEditingController(
    text: '${_settings.convertThreads}',
  );
  late final _merge = TextEditingController(text: '${_settings.mergeThreads}');
  late final _cbr = TextEditingController(text: '${_settings.cbrThreads}');
  late final _batch = TextEditingController(text: '${_settings.batchThreads}');

  @override
  void dispose() {
    _convert.dispose();
    _merge.dispose();
    _cbr.dispose();
    _batch.dispose();
    super.dispose();
  }

  int _threads(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    await ref
        .read(settingsProvider.notifier)
        .update(
          _settings.copyWith(
            convertThreads: _threads(_convert),
            mergeThreads: _threads(_merge),
            cbrThreads: _threads(_cbr),
            batchThreads: _threads(_batch),
          ),
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.settingsTitle),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.appearance, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(l10n.system),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(l10n.light),
                  ),
                  ButtonSegment(value: ThemeMode.dark, label: Text(l10n.dark)),
                ],
                selected: {_settings.themeMode},
                onSelectionChanged: (s) => setState(
                  () => _settings = _settings.copyWith(themeMode: s.first),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _settings.languageCode,
                decoration: InputDecoration(labelText: l10n.language),
                items: [
                  DropdownMenuItem(value: '', child: Text(l10n.system)),
                  DropdownMenuItem(value: 'en', child: Text(l10n.english)),
                  DropdownMenuItem(value: 'it', child: Text(l10n.italian)),
                ],
                onChanged: (v) => setState(
                  () => _settings = _settings.copyWith(languageCode: v ?? ''),
                ),
              ),
              const SizedBox(height: 16),
              Text(l10n.defaultThreads, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _threadField(l10n.convertLabel, _convert)),
                  const SizedBox(width: 8),
                  Expanded(child: _threadField(l10n.mergeLabel, _merge)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _threadField(l10n.cbrLabel, _cbr)),
                  const SizedBox(width: 8),
                  Expanded(child: _threadField(l10n.batchEdit, _batch)),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.keepBackupsByDefault),
                value: _settings.backupByDefault,
                onChanged: (v) => setState(
                  () => _settings = _settings.copyWith(backupByDefault: v),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(l10n.save)),
      ],
    );
  }

  Widget _threadField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
    );
  }
}
