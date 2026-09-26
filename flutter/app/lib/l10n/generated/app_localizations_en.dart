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
  String get up => 'Up';

  @override
  String get cancelSelection => 'Cancel selection';

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String get openSource => 'Open source';

  @override
  String get openLocalFolder => 'Open local folder';

  @override
  String get connectSmbShare => 'Connect to SMB share';

  @override
  String get actions => 'Actions';

  @override
  String get details => 'Details';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get close => 'Close';

  @override
  String get apply => 'Apply';

  @override
  String get clear => 'Clear';

  @override
  String get undo => 'Undo';

  @override
  String get search => 'Search';

  @override
  String get backup => 'Backup';

  @override
  String get delete => 'Delete';

  @override
  String get validate => 'Validate';

  @override
  String get convertWebp => 'Convert to WebP';

  @override
  String get convert => 'Convert';

  @override
  String get removeComicInfo => 'Remove ComicInfo';

  @override
  String get mergeChapters => 'Merge chapters';

  @override
  String get convertCbr => 'Convert CBR to CBZ';

  @override
  String get batchEdit => 'Batch edit';

  @override
  String get batchEditPages => 'Batch edit pages';

  @override
  String get convertCbz => 'Convert to CBZ';

  @override
  String get editPages => 'Edit pages…';

  @override
  String get editComicInfo => 'Edit ComicInfo…';

  @override
  String get editPage => 'Edit page';

  @override
  String get addImageInternet => 'Add image from internet';

  @override
  String get deleteSelected => 'Delete selected';

  @override
  String get moveEarlier => 'Move earlier';

  @override
  String get moveLater => 'Move later';

  @override
  String get renumberPages => 'Renumber pages';

  @override
  String get revertChanges => 'Revert changes';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get revert => 'Revert';

  @override
  String get settings => 'Settings';

  @override
  String get jobValidate => 'Validate';

  @override
  String get jobMerge => 'Merge';

  @override
  String get jobCbrToCbz => 'CBR → CBZ';

  @override
  String get jobComicInfo => 'ComicInfo';

  @override
  String get planning => 'Planning…';

  @override
  String get starting => 'Starting…';

  @override
  String get noJobRunning => 'No job running';

  @override
  String validatingFiles(int count) {
    return 'Validating $count file(s)…';
  }

  @override
  String validationFailed(String error) {
    return 'Validation failed: $error';
  }

  @override
  String get noCbzToMerge => 'No CBZ files to merge';

  @override
  String createdVolumes(int count) {
    return 'Created $count volume(s)';
  }

  @override
  String get mergeProducedNoVolumes => 'Merge produced no volumes';

  @override
  String mergeFailed(String error) {
    return 'Merge failed: $error';
  }

  @override
  String get cbrReadOnlyConvertFirst =>
      'CBR archives are read-only — convert them first';

  @override
  String editingFiles(int count) {
    return 'Editing $count file(s)…';
  }

  @override
  String editedFiles(int ok, int total) {
    return 'Edited $ok of $total file(s)';
  }

  @override
  String batchEditFailed(String error) {
    return 'Batch edit failed: $error';
  }

  @override
  String convertingFiles(int count) {
    return 'Converting $count file(s)…';
  }

  @override
  String conversionFailed(String error) {
    return 'Conversion failed: $error';
  }

  @override
  String get noCbrToConvert => 'No CBR files to convert';

  @override
  String get cbrSupportMissing =>
      'CBR support requires libarchive, which is not available';

  @override
  String cbrConversionFailed(String error) {
    return 'CBR conversion failed: $error';
  }

  @override
  String scanningFiles(int count) {
    return 'Scanning $count file(s)…';
  }

  @override
  String comicInfoRemoved(int changed, int scanned, int skipped) {
    return 'ComicInfo removed from $changed of $scanned file(s), $skipped already clean';
  }

  @override
  String comicInfoRemovedWithErrors(
    int changed,
    int scanned,
    int skipped,
    int errors,
  ) {
    return 'ComicInfo removed from $changed of $scanned file(s), $skipped already clean, $errors error(s)';
  }

  @override
  String removeFailed(String error) {
    return 'Remove failed: $error';
  }

  @override
  String readingName(String name) {
    return 'Reading $name';
  }

  @override
  String cannotReadName(String name, String error) {
    return 'Cannot read $name: $error';
  }

  @override
  String savingName(String name) {
    return 'Saving $name';
  }

  @override
  String comicInfoSaved(String name) {
    return 'ComicInfo saved for $name';
  }

  @override
  String saveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String get readOnly => 'read-only';

  @override
  String get noPages => 'No pages';

  @override
  String convertSummary(int count, int quality) {
    return '$count file(s): WebP q$quality, only if smaller, ComicInfo filtered, pages renumbered.';
  }

  @override
  String get originals => 'Originals';

  @override
  String get originalsRenamed => 'Originals are renamed to <name>_OLD.cbz.';

  @override
  String get originalsOverwritten =>
      'Originals are overwritten with no backup.';

  @override
  String get parallelFiles => 'Parallel files (0 = auto)';

  @override
  String get autoThreadsCapped8 =>
      'Automatic uses one worker per CPU core, capped at 8.';

  @override
  String get conversionResults => 'Conversion results';

  @override
  String get allFilesConverted => 'All files converted.';

  @override
  String convertedCount(int count) {
    return '$count converted';
  }

  @override
  String keptPages(int count) {
    return '$count page(s) kept';
  }

  @override
  String failedCount(int count) {
    return '$count failed';
  }

  @override
  String pagesToWebp(int count) {
    return '$count page(s) to WebP';
  }

  @override
  String savedSize(String size) {
    return '$size saved';
  }

  @override
  String cbrSummary(int count) {
    return '$count CBR archive(s). ComicInfo.xml and non-image entries are dropped, images renumbered page_NNNN.*.';
  }

  @override
  String get skipExistingTargets => 'Skip existing .cbz targets';

  @override
  String get deleteCbrSource => 'Delete the .cbr source after conversion';

  @override
  String get autoThreadsCapped4 =>
      'Automatic uses one worker per CPU core, capped at 4.';

  @override
  String get cbrResults => 'CBR → CBZ results';

  @override
  String get allDone => 'All done.';

  @override
  String skippedCount(int count) {
    return '$count skipped';
  }

  @override
  String pagesCount(int count) {
    return '$count page(s)';
  }

  @override
  String batchEditTitle(int count) {
    return 'Batch edit — $count file(s)';
  }

  @override
  String get resizePercent => 'Resize %';

  @override
  String get splitPages => 'Split pages';

  @override
  String splitStatus(int lines, int pieces) {
    return '$lines line(s) → $pieces pieces';
  }

  @override
  String get off => 'Off';

  @override
  String get rows => 'Rows';

  @override
  String get columns => 'Columns';

  @override
  String get lines => 'Lines';

  @override
  String get backupOriginals => 'Backup originals (_OLD.cbz)';

  @override
  String get grayscale => 'Grayscale';

  @override
  String get sepia => 'Sepia';

  @override
  String get invert => 'Invert';

  @override
  String get brightness => 'Brightness';

  @override
  String get contrast => 'Contrast';

  @override
  String get saturation => 'Saturation';

  @override
  String get gamma => 'Gamma';

  @override
  String get rGain => 'R gain';

  @override
  String get gGain => 'G gain';

  @override
  String get bGain => 'B gain';

  @override
  String get mergeTitle => 'Merge chapters into volumes';

  @override
  String seriesLabel(String name) {
    return 'Series: $name';
  }

  @override
  String get chapterFrom => 'Chapter from';

  @override
  String get chapterTo => 'Chapter to (empty = all)';

  @override
  String get autoCpv => 'Automatic chapters per volume';

  @override
  String calculatedCpv(String cpv) {
    return 'Calculated: $cpv';
  }

  @override
  String noExistingVolumesDefault(int cpv) {
    return 'No existing volumes — default $cpv';
  }

  @override
  String get chaptersPerVolume => 'Chapters per volume';

  @override
  String get forceRemaining => 'Force remaining chapters into last volume';

  @override
  String get generateComicInfoPerVolume => 'Generate ComicInfo.xml per volume';

  @override
  String get parallelVolumes => 'Parallel volumes (0 = auto)';

  @override
  String get customSequence => 'Custom sequence…';

  @override
  String sequenceValue(String list) {
    return 'Sequence: $list';
  }

  @override
  String get preview => 'Preview';

  @override
  String get nothingToMerge => 'Nothing to merge.';

  @override
  String volumesWillBeCreated(int count) {
    return '$count volume(s) will be created';
  }

  @override
  String volumeAndChapters(String name, int count) {
    return '$name — $count chapter(s)';
  }

  @override
  String get merge => 'Merge';

  @override
  String get customSequenceTitle => 'Custom sequence';

  @override
  String sequenceSummary(int chapters, int assigned, int remaining) {
    return '$chapters chapters, $assigned assigned, $remaining to go';
  }

  @override
  String get nextVolume => 'Next vol.';

  @override
  String get addVolume => 'Add volume';

  @override
  String get useSequence => 'Use sequence';

  @override
  String comicInfoTitle(String name) {
    return 'ComicInfo — $name';
  }

  @override
  String get seriesField => 'Series';

  @override
  String get numberField => 'Number';

  @override
  String get volumeField => 'Volume';

  @override
  String get titleField => 'Title';

  @override
  String get countField => 'Count';

  @override
  String get writerField => 'Writer';

  @override
  String get pencillerField => 'Penciller';

  @override
  String get publisherField => 'Publisher';

  @override
  String get genreField => 'Genre';

  @override
  String get yearField => 'Year';

  @override
  String get monthField => 'Month';

  @override
  String get dayField => 'Day';

  @override
  String get pageCountField => 'Page count';

  @override
  String get communityRatingField => 'Community rating';

  @override
  String get languageIsoField => 'Language ISO';

  @override
  String get mangaField => 'Manga';

  @override
  String get ageRatingField => 'Age rating';

  @override
  String get webField => 'Web';

  @override
  String get summaryField => 'Summary';

  @override
  String get editPageTitle => 'Edit page';

  @override
  String cannotDecodePage(String name) {
    return 'Cannot decode $name.';
  }

  @override
  String editPageName(String name) {
    return 'Edit $name';
  }

  @override
  String get size => 'Size';

  @override
  String get width => 'Width';

  @override
  String get height => 'Height';

  @override
  String get keepAspectRatio => 'Keep aspect ratio';

  @override
  String get splitPage => 'Split page';

  @override
  String piecesCount(int count) {
    return '$count pieces';
  }

  @override
  String linesCount(int count) {
    return '$count line(s)';
  }

  @override
  String get cutHint =>
      'Tap the preview to add a cut, drag to move it, long-press to remove.';

  @override
  String outputLine(String ext, String pages) {
    return 'Output: $ext ($pages)';
  }

  @override
  String get onePage => '1 page';

  @override
  String manyPages(int count) {
    return '$count pages';
  }

  @override
  String get changesSaved => 'Changes saved';

  @override
  String pageNumberLabel(int number) {
    return 'Page $number';
  }

  @override
  String pendingChanges(int count) {
    return '$count pending change(s)';
  }

  @override
  String get validationResults => 'Validation results';

  @override
  String validCount(int count) {
    return '$count valid';
  }

  @override
  String failedWithErrors(int count) {
    return '$count with errors';
  }

  @override
  String get allArchivesValid => 'All archives are valid.';

  @override
  String pageErrors(int count) {
    return '$count page error(s)';
  }

  @override
  String get copyReport => 'Copy report';

  @override
  String reportHeader(int count, int valid, int failed) {
    return 'Validation report — $count file(s): $valid ok, $failed failed';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get appearance => 'Appearance';

  @override
  String get system => 'System';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get language => 'Language';

  @override
  String get english => 'English';

  @override
  String get italian => 'Italiano';

  @override
  String get defaultThreads => 'Default threads (0 = auto)';

  @override
  String get convertLabel => 'Convert';

  @override
  String get mergeLabel => 'Merge';

  @override
  String get cbrLabel => 'CBR';

  @override
  String get keepBackupsByDefault => 'Keep _OLD backups by default';

  @override
  String get addImageTitle => 'Add image from internet';

  @override
  String get source => 'Source';

  @override
  String get searchHint => 'Search (or paste an image URL)';

  @override
  String get noResultsYet => 'No results yet';

  @override
  String downloadFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String get providerAll => 'All sources';

  @override
  String get providerMangaDex => 'MangaDex (manga volumes)';

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
  String get providerUrl => 'Paste a URL';

  @override
  String get errNoImages => 'No images found';

  @override
  String get errImageDecode => 'Image could not be decoded';

  @override
  String get errNotZip => 'Not a valid ZIP archive';

  @override
  String get errNotEnoughChapters => 'Not enough chapters for a full volume';

  @override
  String get errNoMatchingChapters => 'No matching chapter files found';

  @override
  String get errMergeCancelled => 'Merge cancelled';

  @override
  String get errMergeRollback =>
      'Error during merge — created volumes have been removed';

  @override
  String get errTargetExists => 'Target exists — skipped';

  @override
  String get errUnreadableCbr => 'Unable to read CBR archive';

  @override
  String get errEmptyResponse => 'Empty response';

  @override
  String get errImageTooLarge => 'Image exceeds 20 MB';

  @override
  String get errFailedToWrite => 'Failed to write';

  @override
  String errCouldNotDecodePage(String name) {
    return 'Page $name could not be decoded';
  }

  @override
  String get errInvalid => 'Invalid';

  @override
  String get cancelling => 'Cancelling…';

  @override
  String get cancellationRequested => 'Cancellation requested';

  @override
  String progressEdited(int done, int total) {
    return 'Edited $done/$total';
  }

  @override
  String progressConverted(int done, int total) {
    return 'Converted $done/$total';
  }

  @override
  String progressBuildingVolumes(int done, int total) {
    return 'Building volumes ($done/$total)';
  }

  @override
  String get host => 'Host';

  @override
  String get share => 'Share';

  @override
  String get userOptional => 'User (optional)';

  @override
  String get passwordOptional => 'Password (optional)';

  @override
  String get required => 'Required';

  @override
  String get connect => 'Connect';
}
