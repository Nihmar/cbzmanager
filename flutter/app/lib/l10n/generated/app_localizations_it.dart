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
  String get up => 'Su';

  @override
  String get cancelSelection => 'Annulla selezione';

  @override
  String selectedCount(int count) {
    return '$count selezionati';
  }

  @override
  String get openSource => 'Apri sorgente';

  @override
  String get openLocalFolder => 'Apri cartella locale';

  @override
  String get connectSmbShare => 'Connetti a condivisione SMB';

  @override
  String get actions => 'Azioni';

  @override
  String get details => 'Dettagli';

  @override
  String get cancel => 'Annulla';

  @override
  String get save => 'Salva';

  @override
  String get close => 'Chiudi';

  @override
  String get apply => 'Applica';

  @override
  String get clear => 'Pulisci';

  @override
  String get undo => 'Annulla ultimo';

  @override
  String get search => 'Cerca';

  @override
  String get backup => 'Backup';

  @override
  String get delete => 'Elimina';

  @override
  String get validate => 'Valida';

  @override
  String get convertWebp => 'Converti in WebP';

  @override
  String get convert => 'Converti';

  @override
  String get removeComicInfo => 'Rimuovi ComicInfo';

  @override
  String get mergeChapters => 'Unisci capitoli';

  @override
  String get convertCbr => 'Converti CBR in CBZ';

  @override
  String get batchEdit => 'Modifica batch';

  @override
  String get batchEditPages => 'Modifica pagine in batch';

  @override
  String get convertCbz => 'Converti in CBZ';

  @override
  String get editPages => 'Modifica pagine…';

  @override
  String get editComicInfo => 'Modifica ComicInfo…';

  @override
  String get editPage => 'Modifica pagina';

  @override
  String get addImageInternet => 'Aggiungi immagine da internet';

  @override
  String get deleteSelected => 'Elimina selezionati';

  @override
  String get moveEarlier => 'Sposta prima';

  @override
  String get moveLater => 'Sposta dopo';

  @override
  String get renumberPages => 'Rinumera pagine';

  @override
  String get revertChanges => 'Annulla modifiche';

  @override
  String get saveChanges => 'Salva modifiche';

  @override
  String get revert => 'Annulla';

  @override
  String get settings => 'Impostazioni';

  @override
  String get jobValidate => 'Valida';

  @override
  String get jobMerge => 'Unione';

  @override
  String get jobCbrToCbz => 'CBR → CBZ';

  @override
  String get jobComicInfo => 'ComicInfo';

  @override
  String get planning => 'Pianificazione…';

  @override
  String get starting => 'Avvio…';

  @override
  String get noJobRunning => 'Nessun lavoro in corso';

  @override
  String validatingFiles(int count) {
    return 'Validazione di $count file…';
  }

  @override
  String validationFailed(String error) {
    return 'Validazione non riuscita: $error';
  }

  @override
  String get noCbzToMerge => 'Nessun file CBZ da unire';

  @override
  String createdVolumes(int count) {
    return 'Creati $count volumi';
  }

  @override
  String get mergeProducedNoVolumes => 'L\'unione non ha prodotto volumi';

  @override
  String mergeFailed(String error) {
    return 'Unione non riuscita: $error';
  }

  @override
  String get cbrReadOnlyConvertFirst =>
      'Gli archivi CBR sono di sola lettura — convertili prima';

  @override
  String editingFiles(int count) {
    return 'Modifica di $count file…';
  }

  @override
  String editedFiles(int ok, int total) {
    return 'Modificati $ok di $total file';
  }

  @override
  String batchEditFailed(String error) {
    return 'Modifica batch non riuscita: $error';
  }

  @override
  String convertingFiles(int count) {
    return 'Conversione di $count file…';
  }

  @override
  String conversionFailed(String error) {
    return 'Conversione non riuscita: $error';
  }

  @override
  String get noCbrToConvert => 'Nessun file CBR da convertire';

  @override
  String get cbrSupportMissing =>
      'Il supporto CBR richiede libarchive, che non è disponibile';

  @override
  String cbrConversionFailed(String error) {
    return 'Conversione CBR non riuscita: $error';
  }

  @override
  String scanningFiles(int count) {
    return 'Scansione di $count file…';
  }

  @override
  String comicInfoRemoved(int changed, int scanned, int skipped) {
    return 'ComicInfo rimosso da $changed di $scanned file, $skipped già puliti';
  }

  @override
  String comicInfoRemovedWithErrors(
    int changed,
    int scanned,
    int skipped,
    int errors,
  ) {
    return 'ComicInfo rimosso da $changed di $scanned file, $skipped già puliti, $errors errori';
  }

  @override
  String removeFailed(String error) {
    return 'Rimozione non riuscita: $error';
  }

  @override
  String readingName(String name) {
    return 'Lettura di $name';
  }

  @override
  String cannotReadName(String name, String error) {
    return 'Impossibile leggere $name: $error';
  }

  @override
  String savingName(String name) {
    return 'Salvataggio di $name';
  }

  @override
  String comicInfoSaved(String name) {
    return 'ComicInfo salvato per $name';
  }

  @override
  String saveFailed(String error) {
    return 'Salvataggio non riuscito: $error';
  }

  @override
  String get readOnly => 'sola lettura';

  @override
  String get noPages => 'Nessuna pagina';

  @override
  String convertSummary(int count, int quality) {
    return '$count file: conversione in WebP a qualità $quality.';
  }

  @override
  String get convertQuality => 'Qualità';

  @override
  String get convertOnlyIfSmaller =>
      'Mantieni l\'originale se il WebP non è più piccolo';

  @override
  String get convertSkipExistingWebp => 'Lascia intatte le pagine già in WebP';

  @override
  String get convertKeepComicInfo => 'Mantieni ComicInfo.xml';

  @override
  String get originals => 'Originali';

  @override
  String get originalsRenamed =>
      'Gli originali vengono rinominati in <nome>_OLD.cbz.';

  @override
  String get originalsOverwritten =>
      'Gli originali vengono sovrascritti senza backup.';

  @override
  String get parallelFiles => 'File in parallelo (0 = auto)';

  @override
  String get autoThreadsCapped8 =>
      'Automatico usa un worker per core, fino a 8.';

  @override
  String get conversionResults => 'Risultati conversione';

  @override
  String get allFilesConverted => 'Tutti i file convertiti.';

  @override
  String convertedCount(int count) {
    return '$count convertiti';
  }

  @override
  String keptPages(int count) {
    return '$count pagine mantenute';
  }

  @override
  String failedCount(int count) {
    return '$count non riusciti';
  }

  @override
  String pagesToWebp(int count) {
    return '$count pagine in WebP';
  }

  @override
  String savedSize(String size) {
    return '$size risparmiati';
  }

  @override
  String cbrSummary(int count) {
    return '$count archivi CBR. ComicInfo.xml e le voci non immagine vengono rimossi, le immagini rinominate page_NNNN.*.';
  }

  @override
  String get skipExistingTargets => 'Salta i .cbz già esistenti';

  @override
  String get deleteCbrSource =>
      'Elimina il .cbr di origine dopo la conversione';

  @override
  String get autoThreadsCapped4 =>
      'Automatico usa un worker per core, fino a 4.';

  @override
  String get cbrResults => 'Risultati CBR → CBZ';

  @override
  String get allDone => 'Tutto completato.';

  @override
  String skippedCount(int count) {
    return '$count saltati';
  }

  @override
  String pagesCount(int count) {
    return '$count pagine';
  }

  @override
  String batchEditTitle(int count) {
    return 'Modifica batch — $count file';
  }

  @override
  String get resizePercent => 'Ridimensiona %';

  @override
  String get splitPages => 'Dividi pagine';

  @override
  String splitStatus(int lines, int pieces) {
    return '$lines linee → $pieces parti';
  }

  @override
  String get off => 'Off';

  @override
  String get rows => 'Righe';

  @override
  String get columns => 'Colonne';

  @override
  String get lines => 'Linee';

  @override
  String get backupOriginals => 'Backup degli originali (_OLD.cbz)';

  @override
  String get grayscale => 'Scala di grigi';

  @override
  String get sepia => 'Seppia';

  @override
  String get invert => 'Inverti';

  @override
  String get brightness => 'Luminosità';

  @override
  String get contrast => 'Contrasto';

  @override
  String get saturation => 'Saturazione';

  @override
  String get gamma => 'Gamma';

  @override
  String get rGain => 'Guadagno R';

  @override
  String get gGain => 'Guadagno G';

  @override
  String get bGain => 'Guadagno B';

  @override
  String get mergeTitle => 'Unisci capitoli in volumi';

  @override
  String seriesLabel(String name) {
    return 'Serie: $name';
  }

  @override
  String get chapterFrom => 'Da capitolo';

  @override
  String get chapterTo => 'A capitolo (vuoto = tutti)';

  @override
  String get autoCpv => 'Capitoli per volume automatici';

  @override
  String calculatedCpv(String cpv) {
    return 'Calcolato: $cpv';
  }

  @override
  String noExistingVolumesDefault(int cpv) {
    return 'Nessun volume esistente — predefinito $cpv';
  }

  @override
  String get chaptersPerVolume => 'Capitoli per volume';

  @override
  String get forceRemaining => 'Forza i capitoli rimanenti nell\'ultimo volume';

  @override
  String get generateComicInfoPerVolume => 'Genera ComicInfo.xml per volume';

  @override
  String get parallelVolumes => 'Volumi in parallelo (0 = auto)';

  @override
  String get customSequence => 'Sequenza personalizzata…';

  @override
  String sequenceValue(String list) {
    return 'Sequenza: $list';
  }

  @override
  String get preview => 'Anteprima';

  @override
  String get nothingToMerge => 'Niente da unire.';

  @override
  String volumesWillBeCreated(int count) {
    return 'Verranno creati $count volumi';
  }

  @override
  String volumeAndChapters(String name, int count) {
    return '$name — $count capitoli';
  }

  @override
  String get merge => 'Unisci';

  @override
  String get customSequenceTitle => 'Sequenza personalizzata';

  @override
  String sequenceSummary(int chapters, int assigned, int remaining) {
    return '$chapters capitoli, $assigned assegnati, $remaining da assegnare';
  }

  @override
  String get nextVolume => 'Vol. successivo';

  @override
  String get addVolume => 'Aggiungi volume';

  @override
  String get useSequence => 'Usa sequenza';

  @override
  String comicInfoTitle(String name) {
    return 'ComicInfo — $name';
  }

  @override
  String get seriesField => 'Serie';

  @override
  String get numberField => 'Numero';

  @override
  String get volumeField => 'Volume';

  @override
  String get titleField => 'Titolo';

  @override
  String get countField => 'Totale';

  @override
  String get writerField => 'Sceneggiatore';

  @override
  String get pencillerField => 'Disegnatore';

  @override
  String get publisherField => 'Editore';

  @override
  String get genreField => 'Genere';

  @override
  String get yearField => 'Anno';

  @override
  String get monthField => 'Mese';

  @override
  String get dayField => 'Giorno';

  @override
  String get pageCountField => 'Numero di pagine';

  @override
  String get communityRatingField => 'Voto della community';

  @override
  String get languageIsoField => 'Lingua ISO';

  @override
  String get mangaField => 'Manga';

  @override
  String get ageRatingField => 'Classificazione per età';

  @override
  String get webField => 'Web';

  @override
  String get summaryField => 'Trama';

  @override
  String get editPageTitle => 'Modifica pagina';

  @override
  String cannotDecodePage(String name) {
    return 'Impossibile decodificare $name.';
  }

  @override
  String editPageName(String name) {
    return 'Modifica $name';
  }

  @override
  String get size => 'Dimensione';

  @override
  String get width => 'Larghezza';

  @override
  String get height => 'Altezza';

  @override
  String get keepAspectRatio => 'Mantieni proporzioni';

  @override
  String get splitPage => 'Dividi pagina';

  @override
  String piecesCount(int count) {
    return '$count parti';
  }

  @override
  String linesCount(int count) {
    return '$count linee';
  }

  @override
  String get cutHint =>
      'Tocca l\'anteprima per aggiungere un taglio, trascina per spostarlo, tieni premuto per rimuoverlo.';

  @override
  String outputLine(String ext, String pages) {
    return 'Output: $ext ($pages)';
  }

  @override
  String get onePage => '1 pagina';

  @override
  String manyPages(int count) {
    return '$count pagine';
  }

  @override
  String get changesSaved => 'Modifiche salvate';

  @override
  String pageNumberLabel(int number) {
    return 'Pagina $number';
  }

  @override
  String pendingChanges(int count) {
    return '$count modifiche in sospeso';
  }

  @override
  String get validationResults => 'Risultati validazione';

  @override
  String validCount(int count) {
    return '$count validi';
  }

  @override
  String failedWithErrors(int count) {
    return '$count con errori';
  }

  @override
  String get allArchivesValid => 'Tutti gli archivi sono validi.';

  @override
  String pageErrors(int count) {
    return '$count errori di pagina';
  }

  @override
  String get copyReport => 'Copia report';

  @override
  String reportHeader(int count, int valid, int failed) {
    return 'Report di validazione — $count file: $valid ok, $failed non validi';
  }

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String get appearance => 'Aspetto';

  @override
  String get system => 'Sistema';

  @override
  String get light => 'Chiaro';

  @override
  String get dark => 'Scuro';

  @override
  String get language => 'Lingua';

  @override
  String get english => 'English';

  @override
  String get italian => 'Italiano';

  @override
  String get defaultThreads => 'Thread predefiniti (0 = auto)';

  @override
  String get convertLabel => 'Conversione';

  @override
  String get mergeLabel => 'Unione';

  @override
  String get cbrLabel => 'CBR';

  @override
  String get keepBackupsByDefault =>
      'Mantieni i backup _OLD per impostazione predefinita';

  @override
  String get addImageTitle => 'Aggiungi immagine da internet';

  @override
  String get source => 'Sorgente';

  @override
  String get searchHint => 'Cerca (o incolla l\'URL di un\'immagine)';

  @override
  String get noResultsYet => 'Nessun risultato';

  @override
  String downloadFailed(String error) {
    return 'Download non riuscito: $error';
  }

  @override
  String get providerAll => 'Tutte le sorgenti';

  @override
  String get providerMangaDex => 'MangaDex (volumi manga)';

  @override
  String get providerOpenverse => 'Openverse';

  @override
  String get providerWikimedia => 'Wikimedia Commons';

  @override
  String get providerOpenLibrary => 'Open Library';

  @override
  String get providerArtInstitute => 'Art Institute of Chicago';

  @override
  String get providerMet => 'The Met';

  @override
  String get providerCleveland => 'Cleveland Museum of Art';

  @override
  String get providerWellcome => 'Wellcome Collection';

  @override
  String get providerNasa => 'NASA Images';

  @override
  String get providerUrl => 'Incolla un URL';

  @override
  String get errNoImages => 'Nessuna immagine trovata';

  @override
  String get errImageDecode => 'Impossibile decodificare l\'immagine';

  @override
  String get errNotZip => 'Archivio ZIP non valido';

  @override
  String get errNotEnoughChapters =>
      'Capitoli insufficienti per un volume completo';

  @override
  String get errNoMatchingChapters => 'Nessun file capitolo corrispondente';

  @override
  String get errMergeCancelled => 'Unione annullata';

  @override
  String get errMergeRollback =>
      'Errore durante l\'unione — i volumi creati sono stati rimossi';

  @override
  String get errTargetExists => 'Destinazione già esistente — saltata';

  @override
  String get errUnreadableCbr => 'Impossibile leggere l\'archivio CBR';

  @override
  String get errEmptyResponse => 'Risposta vuota';

  @override
  String get errImageTooLarge => 'Immagine oltre 20 MB';

  @override
  String get errFailedToWrite => 'Scrittura non riuscita';

  @override
  String errCouldNotDecodePage(String name) {
    return 'Impossibile decodificare la pagina $name';
  }

  @override
  String get errInvalid => 'Non valido';

  @override
  String get cancelling => 'Annullamento…';

  @override
  String get cancellationRequested => 'Annullamento richiesto';

  @override
  String progressEdited(int done, int total) {
    return 'Modificati $done/$total';
  }

  @override
  String progressConverted(int done, int total) {
    return 'Convertiti $done/$total';
  }

  @override
  String progressBuildingVolumes(int done, int total) {
    return 'Creazione volumi ($done/$total)';
  }

  @override
  String get host => 'Host';

  @override
  String get share => 'Condivisione';

  @override
  String get userOptional => 'Utente (facoltativo)';

  @override
  String get passwordOptional => 'Password (facoltativa)';

  @override
  String get required => 'Obbligatorio';

  @override
  String get connect => 'Connetti';
}
