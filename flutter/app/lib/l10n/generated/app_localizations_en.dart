// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'CBZ Manager';

  @override
  String get welcomeTitle => 'Open a comics folder';

  @override
  String get welcomeSubtitle =>
      'Choose a local folder or connect to an SMB share.';

  @override
  String get localFolder => 'Local folder';

  @override
  String get smbShare => 'SMB share';

  @override
  String get noArchives => 'No CBZ/CBR files in this folder';

  @override
  String get refresh => 'Refresh';

  @override
  String get select => 'Select';

  @override
  String get selectAll => 'Select all';

  @override
  String get validate => 'Validate';

  @override
  String get convertWebp => 'Convert to WebP';

  @override
  String get removeComicInfo => 'Remove ComicInfo';

  @override
  String get mergeChapters => 'Merge chapters';

  @override
  String get convertCbr => 'Convert CBR to CBZ';

  @override
  String get batchEdit => 'Batch edit pages';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get close => 'Close';

  @override
  String get settings => 'Settings';
}
