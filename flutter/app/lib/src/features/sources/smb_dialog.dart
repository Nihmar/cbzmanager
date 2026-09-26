import 'package:flutter/material.dart';

import 'package:cbzmanager/l10n/generated/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.connectSmbShare),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _host,
                decoration: InputDecoration(
                  labelText: l10n.host,
                  hintText: '192.168.1.10',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.required : null,
              ),
              TextFormField(
                controller: _share,
                decoration: InputDecoration(
                  labelText: l10n.share,
                  hintText: 'Comics',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.required : null,
              ),
              TextFormField(
                controller: _user,
                decoration: InputDecoration(labelText: l10n.userOptional),
              ),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(labelText: l10n.passwordOptional),
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
          child: Text(l10n.connect),
        ),
      ],
    );
  }
}
