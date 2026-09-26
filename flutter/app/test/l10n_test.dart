import 'dart:convert';
import 'dart:io';

import 'package:cbzmanager/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the two ARB files against drift: every template key must have an
/// Italian translation, with the same placeholders in the message text.
void main() {
  Map<String, dynamic> load(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  Set<String> messageKeys(Map<String, dynamic> arb) =>
      arb.keys.where((k) => !k.startsWith('@')).toSet();

  Set<String> placeholdersOf(String message) =>
      RegExp(r'\{([A-Za-z0-9_]+)')
          .allMatches(message)
          .map((m) => m.group(1)!)
          .toSet();

  test('every template key has an Italian translation', () {
    final en = load('lib/l10n/app_en.arb');
    final it = load('lib/l10n/app_it.arb');
    final enKeys = messageKeys(en);
    final itKeys = messageKeys(it);

    expect(
      enKeys.difference(itKeys),
      isEmpty,
      reason: 'keys missing from app_it.arb',
    );
    expect(
      itKeys.difference(enKeys),
      isEmpty,
      reason: 'keys in app_it.arb without a template entry',
    );
  });

  test('placeholders match between the template and the translation', () {
    final en = load('lib/l10n/app_en.arb');
    final it = load('lib/l10n/app_it.arb');

    for (final key in messageKeys(en)) {
      final itMessage = it[key];
      if (itMessage is! String) continue;
      expect(
        placeholdersOf(itMessage),
        placeholdersOf(en[key]! as String),
        reason: 'placeholder mismatch for "$key"',
      );
    }
  });

  testWidgets('the Italian locale renders the Italian translations', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Text(AppLocalizations.of(context).validate),
        ),
      ),
    );
    expect(find.text('Valida'), findsOneWidget);
  });
}
