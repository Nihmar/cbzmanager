import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('it'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'CBZ Manager'**
  String get appTitle;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Open a comics folder'**
  String get welcomeTitle;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a local folder or connect to an SMB share.'**
  String get welcomeSubtitle;

  /// No description provided for @localFolder.
  ///
  /// In en, this message translates to:
  /// **'Local folder'**
  String get localFolder;

  /// No description provided for @smbShare.
  ///
  /// In en, this message translates to:
  /// **'SMB share'**
  String get smbShare;

  /// No description provided for @noArchives.
  ///
  /// In en, this message translates to:
  /// **'No CBZ/CBR files in this folder'**
  String get noArchives;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @up.
  ///
  /// In en, this message translates to:
  /// **'Up'**
  String get up;

  /// No description provided for @cancelSelection.
  ///
  /// In en, this message translates to:
  /// **'Cancel selection'**
  String get cancelSelection;

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @openSource.
  ///
  /// In en, this message translates to:
  /// **'Open source'**
  String get openSource;

  /// No description provided for @openLocalFolder.
  ///
  /// In en, this message translates to:
  /// **'Open local folder'**
  String get openLocalFolder;

  /// No description provided for @connectSmbShare.
  ///
  /// In en, this message translates to:
  /// **'Connect to SMB share'**
  String get connectSmbShare;

  /// No description provided for @actions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get actions;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @backup.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backup;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @validate.
  ///
  /// In en, this message translates to:
  /// **'Validate'**
  String get validate;

  /// No description provided for @convertWebp.
  ///
  /// In en, this message translates to:
  /// **'Convert to WebP'**
  String get convertWebp;

  /// No description provided for @convert.
  ///
  /// In en, this message translates to:
  /// **'Convert'**
  String get convert;

  /// No description provided for @removeComicInfo.
  ///
  /// In en, this message translates to:
  /// **'Remove ComicInfo'**
  String get removeComicInfo;

  /// No description provided for @mergeChapters.
  ///
  /// In en, this message translates to:
  /// **'Merge chapters'**
  String get mergeChapters;

  /// No description provided for @convertCbr.
  ///
  /// In en, this message translates to:
  /// **'Convert CBR to CBZ'**
  String get convertCbr;

  /// No description provided for @batchEdit.
  ///
  /// In en, this message translates to:
  /// **'Batch edit'**
  String get batchEdit;

  /// No description provided for @batchEditPages.
  ///
  /// In en, this message translates to:
  /// **'Batch edit pages'**
  String get batchEditPages;

  /// No description provided for @convertCbz.
  ///
  /// In en, this message translates to:
  /// **'Convert to CBZ'**
  String get convertCbz;

  /// No description provided for @editPages.
  ///
  /// In en, this message translates to:
  /// **'Edit pages…'**
  String get editPages;

  /// No description provided for @editComicInfo.
  ///
  /// In en, this message translates to:
  /// **'Edit ComicInfo…'**
  String get editComicInfo;

  /// No description provided for @editPage.
  ///
  /// In en, this message translates to:
  /// **'Edit page'**
  String get editPage;

  /// No description provided for @addImageInternet.
  ///
  /// In en, this message translates to:
  /// **'Add image from internet'**
  String get addImageInternet;

  /// No description provided for @deleteSelected.
  ///
  /// In en, this message translates to:
  /// **'Delete selected'**
  String get deleteSelected;

  /// No description provided for @moveEarlier.
  ///
  /// In en, this message translates to:
  /// **'Move earlier'**
  String get moveEarlier;

  /// No description provided for @moveLater.
  ///
  /// In en, this message translates to:
  /// **'Move later'**
  String get moveLater;

  /// No description provided for @renumberPages.
  ///
  /// In en, this message translates to:
  /// **'Renumber pages'**
  String get renumberPages;

  /// No description provided for @revertChanges.
  ///
  /// In en, this message translates to:
  /// **'Revert changes'**
  String get revertChanges;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @revert.
  ///
  /// In en, this message translates to:
  /// **'Revert'**
  String get revert;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @jobValidate.
  ///
  /// In en, this message translates to:
  /// **'Validate'**
  String get jobValidate;

  /// No description provided for @jobMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get jobMerge;

  /// No description provided for @jobCbrToCbz.
  ///
  /// In en, this message translates to:
  /// **'CBR → CBZ'**
  String get jobCbrToCbz;

  /// No description provided for @jobComicInfo.
  ///
  /// In en, this message translates to:
  /// **'ComicInfo'**
  String get jobComicInfo;

  /// No description provided for @planning.
  ///
  /// In en, this message translates to:
  /// **'Planning…'**
  String get planning;

  /// No description provided for @starting.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get starting;

  /// No description provided for @noJobRunning.
  ///
  /// In en, this message translates to:
  /// **'No job running'**
  String get noJobRunning;

  /// No description provided for @validatingFiles.
  ///
  /// In en, this message translates to:
  /// **'Validating {count} file(s)…'**
  String validatingFiles(int count);

  /// No description provided for @validationFailed.
  ///
  /// In en, this message translates to:
  /// **'Validation failed: {error}'**
  String validationFailed(String error);

  /// No description provided for @noCbzToMerge.
  ///
  /// In en, this message translates to:
  /// **'No CBZ files to merge'**
  String get noCbzToMerge;

  /// No description provided for @createdVolumes.
  ///
  /// In en, this message translates to:
  /// **'Created {count} volume(s)'**
  String createdVolumes(int count);

  /// No description provided for @mergeProducedNoVolumes.
  ///
  /// In en, this message translates to:
  /// **'Merge produced no volumes'**
  String get mergeProducedNoVolumes;

  /// No description provided for @mergeFailed.
  ///
  /// In en, this message translates to:
  /// **'Merge failed: {error}'**
  String mergeFailed(String error);

  /// No description provided for @cbrReadOnlyConvertFirst.
  ///
  /// In en, this message translates to:
  /// **'CBR archives are read-only — convert them first'**
  String get cbrReadOnlyConvertFirst;

  /// No description provided for @editingFiles.
  ///
  /// In en, this message translates to:
  /// **'Editing {count} file(s)…'**
  String editingFiles(int count);

  /// No description provided for @editedFiles.
  ///
  /// In en, this message translates to:
  /// **'Edited {ok} of {total} file(s)'**
  String editedFiles(int ok, int total);

  /// No description provided for @batchEditFailed.
  ///
  /// In en, this message translates to:
  /// **'Batch edit failed: {error}'**
  String batchEditFailed(String error);

  /// No description provided for @convertingFiles.
  ///
  /// In en, this message translates to:
  /// **'Converting {count} file(s)…'**
  String convertingFiles(int count);

  /// No description provided for @conversionFailed.
  ///
  /// In en, this message translates to:
  /// **'Conversion failed: {error}'**
  String conversionFailed(String error);

  /// No description provided for @noCbrToConvert.
  ///
  /// In en, this message translates to:
  /// **'No CBR files to convert'**
  String get noCbrToConvert;

  /// No description provided for @cbrSupportMissing.
  ///
  /// In en, this message translates to:
  /// **'CBR support requires libarchive, which is not available'**
  String get cbrSupportMissing;

  /// No description provided for @cbrConversionFailed.
  ///
  /// In en, this message translates to:
  /// **'CBR conversion failed: {error}'**
  String cbrConversionFailed(String error);

  /// No description provided for @scanningFiles.
  ///
  /// In en, this message translates to:
  /// **'Scanning {count} file(s)…'**
  String scanningFiles(int count);

  /// No description provided for @comicInfoRemoved.
  ///
  /// In en, this message translates to:
  /// **'ComicInfo removed from {changed} of {scanned} file(s), {skipped} already clean'**
  String comicInfoRemoved(int changed, int scanned, int skipped);

  /// No description provided for @comicInfoRemovedWithErrors.
  ///
  /// In en, this message translates to:
  /// **'ComicInfo removed from {changed} of {scanned} file(s), {skipped} already clean, {errors} error(s)'**
  String comicInfoRemovedWithErrors(
    int changed,
    int scanned,
    int skipped,
    int errors,
  );

  /// No description provided for @removeFailed.
  ///
  /// In en, this message translates to:
  /// **'Remove failed: {error}'**
  String removeFailed(String error);

  /// No description provided for @readingName.
  ///
  /// In en, this message translates to:
  /// **'Reading {name}'**
  String readingName(String name);

  /// No description provided for @cannotReadName.
  ///
  /// In en, this message translates to:
  /// **'Cannot read {name}: {error}'**
  String cannotReadName(String name, String error);

  /// No description provided for @savingName.
  ///
  /// In en, this message translates to:
  /// **'Saving {name}'**
  String savingName(String name);

  /// No description provided for @comicInfoSaved.
  ///
  /// In en, this message translates to:
  /// **'ComicInfo saved for {name}'**
  String comicInfoSaved(String name);

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String saveFailed(String error);

  /// No description provided for @readOnly.
  ///
  /// In en, this message translates to:
  /// **'read-only'**
  String get readOnly;

  /// No description provided for @noPages.
  ///
  /// In en, this message translates to:
  /// **'No pages'**
  String get noPages;

  /// No description provided for @convertSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} file(s) — WebP conversion at quality {quality}.'**
  String convertSummary(int count, int quality);

  /// No description provided for @convertQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get convertQuality;

  /// No description provided for @convertOnlyIfSmaller.
  ///
  /// In en, this message translates to:
  /// **'Keep the original when WebP is not smaller'**
  String get convertOnlyIfSmaller;

  /// No description provided for @convertSkipExistingWebp.
  ///
  /// In en, this message translates to:
  /// **'Leave existing WebP pages untouched'**
  String get convertSkipExistingWebp;

  /// No description provided for @convertKeepComicInfo.
  ///
  /// In en, this message translates to:
  /// **'Keep ComicInfo.xml'**
  String get convertKeepComicInfo;

  /// No description provided for @originals.
  ///
  /// In en, this message translates to:
  /// **'Originals'**
  String get originals;

  /// No description provided for @originalsRenamed.
  ///
  /// In en, this message translates to:
  /// **'Originals are renamed to <name>_OLD.cbz.'**
  String get originalsRenamed;

  /// No description provided for @originalsOverwritten.
  ///
  /// In en, this message translates to:
  /// **'Originals are overwritten with no backup.'**
  String get originalsOverwritten;

  /// No description provided for @parallelFiles.
  ///
  /// In en, this message translates to:
  /// **'Parallel files (0 = auto)'**
  String get parallelFiles;

  /// No description provided for @autoThreadsCapped8.
  ///
  /// In en, this message translates to:
  /// **'Automatic uses one worker per CPU core, capped at 8.'**
  String get autoThreadsCapped8;

  /// No description provided for @conversionResults.
  ///
  /// In en, this message translates to:
  /// **'Conversion results'**
  String get conversionResults;

  /// No description provided for @allFilesConverted.
  ///
  /// In en, this message translates to:
  /// **'All files converted.'**
  String get allFilesConverted;

  /// No description provided for @convertedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} converted'**
  String convertedCount(int count);

  /// No description provided for @keptPages.
  ///
  /// In en, this message translates to:
  /// **'{count} page(s) kept'**
  String keptPages(int count);

  /// No description provided for @failedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} failed'**
  String failedCount(int count);

  /// No description provided for @pagesToWebp.
  ///
  /// In en, this message translates to:
  /// **'{count} page(s) to WebP'**
  String pagesToWebp(int count);

  /// No description provided for @savedSize.
  ///
  /// In en, this message translates to:
  /// **'{size} saved'**
  String savedSize(String size);

  /// No description provided for @cbrSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} CBR archive(s). ComicInfo.xml and non-image entries are dropped, images renumbered page_NNNN.*.'**
  String cbrSummary(int count);

  /// No description provided for @skipExistingTargets.
  ///
  /// In en, this message translates to:
  /// **'Skip existing .cbz targets'**
  String get skipExistingTargets;

  /// No description provided for @deleteCbrSource.
  ///
  /// In en, this message translates to:
  /// **'Delete the .cbr source after conversion'**
  String get deleteCbrSource;

  /// No description provided for @autoThreadsCapped4.
  ///
  /// In en, this message translates to:
  /// **'Automatic uses one worker per CPU core, capped at 4.'**
  String get autoThreadsCapped4;

  /// No description provided for @cbrResults.
  ///
  /// In en, this message translates to:
  /// **'CBR → CBZ results'**
  String get cbrResults;

  /// No description provided for @allDone.
  ///
  /// In en, this message translates to:
  /// **'All done.'**
  String get allDone;

  /// No description provided for @skippedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} skipped'**
  String skippedCount(int count);

  /// No description provided for @pagesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} page(s)'**
  String pagesCount(int count);

  /// No description provided for @batchEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch edit — {count} file(s)'**
  String batchEditTitle(int count);

  /// No description provided for @resizePercent.
  ///
  /// In en, this message translates to:
  /// **'Resize %'**
  String get resizePercent;

  /// No description provided for @splitPages.
  ///
  /// In en, this message translates to:
  /// **'Split pages'**
  String get splitPages;

  /// No description provided for @splitStatus.
  ///
  /// In en, this message translates to:
  /// **'{lines} line(s) → {pieces} pieces'**
  String splitStatus(int lines, int pieces);

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @rows.
  ///
  /// In en, this message translates to:
  /// **'Rows'**
  String get rows;

  /// No description provided for @columns.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get columns;

  /// No description provided for @lines.
  ///
  /// In en, this message translates to:
  /// **'Lines'**
  String get lines;

  /// No description provided for @backupOriginals.
  ///
  /// In en, this message translates to:
  /// **'Backup originals (_OLD.cbz)'**
  String get backupOriginals;

  /// No description provided for @grayscale.
  ///
  /// In en, this message translates to:
  /// **'Grayscale'**
  String get grayscale;

  /// No description provided for @sepia.
  ///
  /// In en, this message translates to:
  /// **'Sepia'**
  String get sepia;

  /// No description provided for @invert.
  ///
  /// In en, this message translates to:
  /// **'Invert'**
  String get invert;

  /// No description provided for @brightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get brightness;

  /// No description provided for @contrast.
  ///
  /// In en, this message translates to:
  /// **'Contrast'**
  String get contrast;

  /// No description provided for @saturation.
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get saturation;

  /// No description provided for @gamma.
  ///
  /// In en, this message translates to:
  /// **'Gamma'**
  String get gamma;

  /// No description provided for @rGain.
  ///
  /// In en, this message translates to:
  /// **'R gain'**
  String get rGain;

  /// No description provided for @gGain.
  ///
  /// In en, this message translates to:
  /// **'G gain'**
  String get gGain;

  /// No description provided for @bGain.
  ///
  /// In en, this message translates to:
  /// **'B gain'**
  String get bGain;

  /// No description provided for @mergeTitle.
  ///
  /// In en, this message translates to:
  /// **'Merge chapters into volumes'**
  String get mergeTitle;

  /// No description provided for @seriesLabel.
  ///
  /// In en, this message translates to:
  /// **'Series: {name}'**
  String seriesLabel(String name);

  /// No description provided for @chapterFrom.
  ///
  /// In en, this message translates to:
  /// **'Chapter from'**
  String get chapterFrom;

  /// No description provided for @chapterTo.
  ///
  /// In en, this message translates to:
  /// **'Chapter to (empty = all)'**
  String get chapterTo;

  /// No description provided for @autoCpv.
  ///
  /// In en, this message translates to:
  /// **'Automatic chapters per volume'**
  String get autoCpv;

  /// No description provided for @calculatedCpv.
  ///
  /// In en, this message translates to:
  /// **'Calculated: {cpv}'**
  String calculatedCpv(String cpv);

  /// No description provided for @noExistingVolumesDefault.
  ///
  /// In en, this message translates to:
  /// **'No existing volumes — default {cpv}'**
  String noExistingVolumesDefault(int cpv);

  /// No description provided for @chaptersPerVolume.
  ///
  /// In en, this message translates to:
  /// **'Chapters per volume'**
  String get chaptersPerVolume;

  /// No description provided for @forceRemaining.
  ///
  /// In en, this message translates to:
  /// **'Force remaining chapters into last volume'**
  String get forceRemaining;

  /// No description provided for @generateComicInfoPerVolume.
  ///
  /// In en, this message translates to:
  /// **'Generate ComicInfo.xml per volume'**
  String get generateComicInfoPerVolume;

  /// No description provided for @parallelVolumes.
  ///
  /// In en, this message translates to:
  /// **'Parallel volumes (0 = auto)'**
  String get parallelVolumes;

  /// No description provided for @customSequence.
  ///
  /// In en, this message translates to:
  /// **'Custom sequence…'**
  String get customSequence;

  /// No description provided for @sequenceValue.
  ///
  /// In en, this message translates to:
  /// **'Sequence: {list}'**
  String sequenceValue(String list);

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @nothingToMerge.
  ///
  /// In en, this message translates to:
  /// **'Nothing to merge.'**
  String get nothingToMerge;

  /// No description provided for @volumesWillBeCreated.
  ///
  /// In en, this message translates to:
  /// **'{count} volume(s) will be created'**
  String volumesWillBeCreated(int count);

  /// No description provided for @volumeAndChapters.
  ///
  /// In en, this message translates to:
  /// **'{name} — {count} chapter(s)'**
  String volumeAndChapters(String name, int count);

  /// No description provided for @merge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get merge;

  /// No description provided for @customSequenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom sequence'**
  String get customSequenceTitle;

  /// No description provided for @sequenceSummary.
  ///
  /// In en, this message translates to:
  /// **'{chapters} chapters, {assigned} assigned, {remaining} to go'**
  String sequenceSummary(int chapters, int assigned, int remaining);

  /// No description provided for @nextVolume.
  ///
  /// In en, this message translates to:
  /// **'Next vol.'**
  String get nextVolume;

  /// No description provided for @addVolume.
  ///
  /// In en, this message translates to:
  /// **'Add volume'**
  String get addVolume;

  /// No description provided for @useSequence.
  ///
  /// In en, this message translates to:
  /// **'Use sequence'**
  String get useSequence;

  /// No description provided for @comicInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'ComicInfo — {name}'**
  String comicInfoTitle(String name);

  /// No description provided for @seriesField.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get seriesField;

  /// No description provided for @numberField.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get numberField;

  /// No description provided for @volumeField.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get volumeField;

  /// No description provided for @titleField.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get titleField;

  /// No description provided for @countField.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get countField;

  /// No description provided for @writerField.
  ///
  /// In en, this message translates to:
  /// **'Writer'**
  String get writerField;

  /// No description provided for @pencillerField.
  ///
  /// In en, this message translates to:
  /// **'Penciller'**
  String get pencillerField;

  /// No description provided for @publisherField.
  ///
  /// In en, this message translates to:
  /// **'Publisher'**
  String get publisherField;

  /// No description provided for @genreField.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get genreField;

  /// No description provided for @yearField.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get yearField;

  /// No description provided for @monthField.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get monthField;

  /// No description provided for @dayField.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get dayField;

  /// No description provided for @pageCountField.
  ///
  /// In en, this message translates to:
  /// **'Page count'**
  String get pageCountField;

  /// No description provided for @communityRatingField.
  ///
  /// In en, this message translates to:
  /// **'Community rating'**
  String get communityRatingField;

  /// No description provided for @languageIsoField.
  ///
  /// In en, this message translates to:
  /// **'Language ISO'**
  String get languageIsoField;

  /// No description provided for @mangaField.
  ///
  /// In en, this message translates to:
  /// **'Manga'**
  String get mangaField;

  /// No description provided for @ageRatingField.
  ///
  /// In en, this message translates to:
  /// **'Age rating'**
  String get ageRatingField;

  /// No description provided for @webField.
  ///
  /// In en, this message translates to:
  /// **'Web'**
  String get webField;

  /// No description provided for @summaryField.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get summaryField;

  /// No description provided for @editPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit page'**
  String get editPageTitle;

  /// No description provided for @cannotDecodePage.
  ///
  /// In en, this message translates to:
  /// **'Cannot decode {name}.'**
  String cannotDecodePage(String name);

  /// No description provided for @editPageName.
  ///
  /// In en, this message translates to:
  /// **'Edit {name}'**
  String editPageName(String name);

  /// No description provided for @size.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get size;

  /// No description provided for @width.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get width;

  /// No description provided for @height.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get height;

  /// No description provided for @keepAspectRatio.
  ///
  /// In en, this message translates to:
  /// **'Keep aspect ratio'**
  String get keepAspectRatio;

  /// No description provided for @splitPage.
  ///
  /// In en, this message translates to:
  /// **'Split page'**
  String get splitPage;

  /// No description provided for @piecesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} pieces'**
  String piecesCount(int count);

  /// No description provided for @linesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} line(s)'**
  String linesCount(int count);

  /// No description provided for @cutHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the preview to add a cut, drag to move it, long-press to remove.'**
  String get cutHint;

  /// No description provided for @outputLine.
  ///
  /// In en, this message translates to:
  /// **'Output: {ext} ({pages})'**
  String outputLine(String ext, String pages);

  /// No description provided for @onePage.
  ///
  /// In en, this message translates to:
  /// **'1 page'**
  String get onePage;

  /// No description provided for @manyPages.
  ///
  /// In en, this message translates to:
  /// **'{count} pages'**
  String manyPages(int count);

  /// No description provided for @changesSaved.
  ///
  /// In en, this message translates to:
  /// **'Changes saved'**
  String get changesSaved;

  /// No description provided for @pageNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Page {number}'**
  String pageNumberLabel(int number);

  /// No description provided for @pendingChanges.
  ///
  /// In en, this message translates to:
  /// **'{count} pending change(s)'**
  String pendingChanges(int count);

  /// No description provided for @validationResults.
  ///
  /// In en, this message translates to:
  /// **'Validation results'**
  String get validationResults;

  /// No description provided for @validCount.
  ///
  /// In en, this message translates to:
  /// **'{count} valid'**
  String validCount(int count);

  /// No description provided for @failedWithErrors.
  ///
  /// In en, this message translates to:
  /// **'{count} with errors'**
  String failedWithErrors(int count);

  /// No description provided for @allArchivesValid.
  ///
  /// In en, this message translates to:
  /// **'All archives are valid.'**
  String get allArchivesValid;

  /// No description provided for @pageErrors.
  ///
  /// In en, this message translates to:
  /// **'{count} page error(s)'**
  String pageErrors(int count);

  /// No description provided for @copyReport.
  ///
  /// In en, this message translates to:
  /// **'Copy report'**
  String get copyReport;

  /// No description provided for @reportHeader.
  ///
  /// In en, this message translates to:
  /// **'Validation report — {count} file(s): {valid} ok, {failed} failed'**
  String reportHeader(int count, int valid, int failed);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @italian.
  ///
  /// In en, this message translates to:
  /// **'Italiano'**
  String get italian;

  /// No description provided for @defaultThreads.
  ///
  /// In en, this message translates to:
  /// **'Default threads (0 = auto)'**
  String get defaultThreads;

  /// No description provided for @convertLabel.
  ///
  /// In en, this message translates to:
  /// **'Convert'**
  String get convertLabel;

  /// No description provided for @mergeLabel.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get mergeLabel;

  /// No description provided for @cbrLabel.
  ///
  /// In en, this message translates to:
  /// **'CBR'**
  String get cbrLabel;

  /// No description provided for @keepBackupsByDefault.
  ///
  /// In en, this message translates to:
  /// **'Keep _OLD backups by default'**
  String get keepBackupsByDefault;

  /// No description provided for @addImageTitle.
  ///
  /// In en, this message translates to:
  /// **'Add image from internet'**
  String get addImageTitle;

  /// No description provided for @source.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get source;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search (or paste an image URL)'**
  String get searchHint;

  /// No description provided for @noResultsYet.
  ///
  /// In en, this message translates to:
  /// **'No results yet'**
  String get noResultsYet;

  /// No description provided for @downloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String downloadFailed(String error);

  /// No description provided for @providerAll.
  ///
  /// In en, this message translates to:
  /// **'All sources'**
  String get providerAll;

  /// No description provided for @providerMangaDex.
  ///
  /// In en, this message translates to:
  /// **'MangaDex (manga volumes)'**
  String get providerMangaDex;

  /// No description provided for @providerOpenverse.
  ///
  /// In en, this message translates to:
  /// **'Openverse'**
  String get providerOpenverse;

  /// No description provided for @providerWikimedia.
  ///
  /// In en, this message translates to:
  /// **'Wikimedia Commons'**
  String get providerWikimedia;

  /// No description provided for @providerOpenLibrary.
  ///
  /// In en, this message translates to:
  /// **'Open Library'**
  String get providerOpenLibrary;

  /// No description provided for @providerArtInstitute.
  ///
  /// In en, this message translates to:
  /// **'Art Institute of Chicago'**
  String get providerArtInstitute;

  /// No description provided for @providerMet.
  ///
  /// In en, this message translates to:
  /// **'The Met'**
  String get providerMet;

  /// No description provided for @providerCleveland.
  ///
  /// In en, this message translates to:
  /// **'Cleveland Museum of Art'**
  String get providerCleveland;

  /// No description provided for @providerWellcome.
  ///
  /// In en, this message translates to:
  /// **'Wellcome Collection'**
  String get providerWellcome;

  /// No description provided for @providerNasa.
  ///
  /// In en, this message translates to:
  /// **'NASA Images'**
  String get providerNasa;

  /// No description provided for @providerUrl.
  ///
  /// In en, this message translates to:
  /// **'Paste a URL'**
  String get providerUrl;

  /// No description provided for @errNoImages.
  ///
  /// In en, this message translates to:
  /// **'No images found'**
  String get errNoImages;

  /// No description provided for @errImageDecode.
  ///
  /// In en, this message translates to:
  /// **'Image could not be decoded'**
  String get errImageDecode;

  /// No description provided for @errNotZip.
  ///
  /// In en, this message translates to:
  /// **'Not a valid ZIP archive'**
  String get errNotZip;

  /// No description provided for @errNotEnoughChapters.
  ///
  /// In en, this message translates to:
  /// **'Not enough chapters for a full volume'**
  String get errNotEnoughChapters;

  /// No description provided for @errNoMatchingChapters.
  ///
  /// In en, this message translates to:
  /// **'No matching chapter files found'**
  String get errNoMatchingChapters;

  /// No description provided for @errMergeCancelled.
  ///
  /// In en, this message translates to:
  /// **'Merge cancelled'**
  String get errMergeCancelled;

  /// No description provided for @errMergeRollback.
  ///
  /// In en, this message translates to:
  /// **'Error during merge — created volumes have been removed'**
  String get errMergeRollback;

  /// No description provided for @errTargetExists.
  ///
  /// In en, this message translates to:
  /// **'Target exists — skipped'**
  String get errTargetExists;

  /// No description provided for @errUnreadableCbr.
  ///
  /// In en, this message translates to:
  /// **'Unable to read CBR archive'**
  String get errUnreadableCbr;

  /// No description provided for @errEmptyResponse.
  ///
  /// In en, this message translates to:
  /// **'Empty response'**
  String get errEmptyResponse;

  /// No description provided for @errImageTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Image exceeds 20 MB'**
  String get errImageTooLarge;

  /// No description provided for @errFailedToWrite.
  ///
  /// In en, this message translates to:
  /// **'Failed to write'**
  String get errFailedToWrite;

  /// No description provided for @errCouldNotDecodePage.
  ///
  /// In en, this message translates to:
  /// **'Page {name} could not be decoded'**
  String errCouldNotDecodePage(String name);

  /// No description provided for @errInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid'**
  String get errInvalid;

  /// No description provided for @cancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling…'**
  String get cancelling;

  /// No description provided for @cancellationRequested.
  ///
  /// In en, this message translates to:
  /// **'Cancellation requested'**
  String get cancellationRequested;

  /// No description provided for @progressEdited.
  ///
  /// In en, this message translates to:
  /// **'Edited {done}/{total}'**
  String progressEdited(int done, int total);

  /// No description provided for @progressConverted.
  ///
  /// In en, this message translates to:
  /// **'Converted {done}/{total}'**
  String progressConverted(int done, int total);

  /// No description provided for @progressBuildingVolumes.
  ///
  /// In en, this message translates to:
  /// **'Building volumes ({done}/{total})'**
  String progressBuildingVolumes(int done, int total);

  /// No description provided for @host.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get host;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @userOptional.
  ///
  /// In en, this message translates to:
  /// **'User (optional)'**
  String get userOptional;

  /// No description provided for @passwordOptional.
  ///
  /// In en, this message translates to:
  /// **'Password (optional)'**
  String get passwordOptional;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
