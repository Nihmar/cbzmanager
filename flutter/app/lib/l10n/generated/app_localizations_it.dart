// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'CBZ Manager';

  @override
  String get welcomeTitle => 'Apri una cartella di fumetti';

  @override
  String get welcomeSubtitle =>
      'Scegli una cartella locale o connettiti a una condivisione SMB.';

  @override
  String get localFolder => 'Cartella locale';

  @override
  String get smbShare => 'Condivisione SMB';

  @override
  String get noArchives => 'Nessun file CBZ/CBR in questa cartella';

  @override
  String get refresh => 'Aggiorna';

  @override
  String get select => 'Seleziona';

  @override
  String get selectAll => 'Seleziona tutto';

  @override
  String get validate => 'Valida';

  @override
  String get convertWebp => 'Converti in WebP';

  @override
  String get removeComicInfo => 'Rimuovi ComicInfo';

  @override
  String get mergeChapters => 'Unisci capitoli';

  @override
  String get convertCbr => 'Converti CBR in CBZ';

  @override
  String get batchEdit => 'Modifica batch pagine';

  @override
  String get cancel => 'Annulla';

  @override
  String get save => 'Salva';

  @override
  String get close => 'Chiudi';

  @override
  String get settings => 'Impostazioni';
}
