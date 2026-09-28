import 'package:cbzmanager/l10n/generated/app_localizations.dart';
import 'package:cbzmanager/src/features/batch_edit/batch_edit_service.dart';
import 'package:cbzmanager/src/features/browser/archive_item.dart';
import 'package:cbzmanager/src/util/service_messages.dart';
import 'package:cbzmanager/src/vfs/memory_vfs.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  late AppLocalizations en;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('localizes the page-decode error the services actually produce', () async {
    // The batch-edit isolate throws StateError('Page X could not be
    // decoded'); the service stored '$e' ("Bad state: Page ..."), which the
    // anchored mapping regex never matched, so the raw English text leaked.
    final vfs = MemoryVfs();
    await vfs.writeAll(
      '/book.cbz',
      makeZip({
        'page_001.png': makeSolidPng(20, 20),
        'page_002.png': <int>[0, 1, 2, 3, 4, 5],
      }),
    );

    final outcomes = await const BatchEditService().applyMany(
      vfs,
      const [
        ArchiveItem(name: 'book.cbz', path: '/book.cbz', size: 0, isCbr: false),
      ],
      const BatchEditParams(percent: 50),
    );

    final error = outcomes.single.error!;
    expect(error, isNot(contains('Bad state:')));
    expect(
      localizeServiceMessage(en, error),
      en.errCouldNotDecodePage('page_002.png'),
    );
  });

  test('known service messages are localized', () {
    expect(localizeServiceMessage(en, 'No images found'), en.errNoImages);
    expect(
      localizeServiceMessage(en, 'Not enough chapters for a full volume'),
      en.errNotEnoughChapters,
    );
  });

  test('unknown messages pass through unchanged', () {
    expect(localizeServiceMessage(en, 'Some OS error'), 'Some OS error');
  });
}
