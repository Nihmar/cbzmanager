import 'package:cbzmanager/l10n/generated/app_localizations.dart';

/// Maps the fixed, user-facing messages produced by the pure-Dart services to
/// localized text.
///
/// The service layer has no `BuildContext` and is shared with the headless
/// CLI, so it returns plain strings; this is the single place that turns the
/// known ones into the user's language.  Anything not recognised (exception
/// texts, OS errors, file names) is returned unchanged.
String localizeServiceMessage(AppLocalizations l10n, String message) {
  switch (message) {
    case 'No images found':
    case 'No images found in archive':
      return l10n.errNoImages;
    case 'Image could not be decoded':
      return l10n.errImageDecode;
    case 'Not enough chapters for a full volume':
      return l10n.errNotEnoughChapters;
    case 'No matching chapter files found':
      return l10n.errNoMatchingChapters;
    case 'Merge cancelled':
      return l10n.errMergeCancelled;
    case 'Target exists — skipped':
      return l10n.errTargetExists;
    case '':
      return l10n.errInvalid;
  }
  if (message.startsWith('Not a valid ZIP archive')) return l10n.errNotZip;
  if (message.startsWith('Error during merge')) return l10n.errMergeRollback;
  if (message.startsWith('Unable to read CBR archive')) {
    return l10n.errUnreadableCbr;
  }
  if (message.startsWith('Empty response')) return l10n.errEmptyResponse;
  if (message.startsWith('Image exceeds 20 MB')) return l10n.errImageTooLarge;
  if (message.startsWith('Failed to write')) return l10n.errFailedToWrite;
  final pageDecode = RegExp(r'^Page (.+) could not be decoded$')
      .firstMatch(message);
  if (pageDecode != null) {
    return l10n.errCouldNotDecodePage(pageDecode.group(1)!);
  }
  return message;
}

/// Maps the services' fixed progress messages ("Edited 3/10") to localized
/// text; unknown messages (file names, technical details) pass through.
String localizeProgressMessage(AppLocalizations l10n, String message) {
  final edited = RegExp(r'^Edited (\d+)/(\d+)$').firstMatch(message);
  if (edited != null) {
    return l10n.progressEdited(
      int.parse(edited.group(1)!),
      int.parse(edited.group(2)!),
    );
  }
  final converted = RegExp(r'^Converted (\d+)/(\d+)$').firstMatch(message);
  if (converted != null) {
    return l10n.progressConverted(
      int.parse(converted.group(1)!),
      int.parse(converted.group(2)!),
    );
  }
  final volumes = RegExp(r'^Building volumes \((\d+)/(\d+)\)$')
      .firstMatch(message);
  if (volumes != null) {
    return l10n.progressBuildingVolumes(
      int.parse(volumes.group(1)!),
      int.parse(volumes.group(2)!),
    );
  }
  return message;
}
