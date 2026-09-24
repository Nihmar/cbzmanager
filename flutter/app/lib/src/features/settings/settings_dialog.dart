import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    await ref.read(settingsProvider.notifier).update(
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
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Appearance', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {_settings.themeMode},
                onSelectionChanged: (s) =>
                    setState(() => _settings = _settings.copyWith(themeMode: s.first)),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _settings.languageCode,
                decoration: const InputDecoration(labelText: 'Language'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('System')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'it', child: Text('Italiano')),
                ],
                onChanged: (v) => setState(
                  () => _settings = _settings.copyWith(languageCode: v ?? ''),
                ),
              ),
              const SizedBox(height: 16),
              Text('Default threads (0 = auto)', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _threadField('Convert', _convert)),
                  const SizedBox(width: 8),
                  Expanded(child: _threadField('Merge', _merge)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _threadField('CBR', _cbr)),
                  const SizedBox(width: 8),
                  Expanded(child: _threadField('Batch edit', _batch)),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep _OLD backups by default'),
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
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
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
