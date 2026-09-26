import 'package:flutter/material.dart';

import '../../vfs/smb_vfs.dart';

/// Prompts for SMB connection details. Returns null when cancelled.
Future<SmbConfig?> showSmbConnectDialog(BuildContext context) {
  return showDialog<SmbConfig>(
    context: context,
    builder: (context) => const _SmbConnectDialog(),
  );
}

class _SmbConnectDialog extends StatefulWidget {
  const _SmbConnectDialog();

  @override
  State<_SmbConnectDialog> createState() => _SmbConnectDialogState();
}

class _SmbConnectDialogState extends State<_SmbConnectDialog> {
  final _host = TextEditingController();
  final _share = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _host.dispose();
    _share.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect to SMB share'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _host,
                decoration: const InputDecoration(
                  labelText: 'Host',
                  hintText: '192.168.1.10',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _share,
                decoration: const InputDecoration(
                  labelText: 'Share',
                  hintText: 'Comics',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _user,
                decoration: const InputDecoration(labelText: 'User (optional)'),
              ),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password (optional)',
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
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              SmbConfig(
                host: _host.text.trim(),
                share: _share.text.trim(),
                user: _user.text.trim().isEmpty ? null : _user.text.trim(),
                password: _password.text.isEmpty ? null : _password.text,
              ),
            );
          },
          child: const Text('Connect'),
        ),
      ],
    );
  }
}
