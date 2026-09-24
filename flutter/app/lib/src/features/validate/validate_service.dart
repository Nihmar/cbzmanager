import '../../engine/engine.dart';
import '../../engine/models.dart';
import '../../vfs/vfs.dart';
import '../browser/archive_item.dart';

/// One archive's validation outcome.
class ValidateOutcome {
  const ValidateOutcome({required this.item, required this.result});

  final ArchiveItem item;
  final ValidateResult result;
}

/// Runs deep validation over a set of archives, reporting progress and
/// honouring cooperative cancellation. Never throws: per-file failures become
/// invalid results.
class ValidateService {
  const ValidateService(this.engine);

  final CbzEngine engine;

  Future<List<ValidateOutcome>> validateMany(
    Vfs vfs,
    List<ArchiveItem> items, {
    void Function(int done, int total, String message)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final outcomes = <ValidateOutcome>[];
    final total = items.length;
    for (var i = 0; i < total; i++) {
      if (isCancelled?.call() ?? false) break;
      final item = items[i];
      onProgress?.call(i, total, 'Validating ${item.name}');

      ValidateResult result;
      try {
        final bytes = await vfs.readAll(item.path);
        result = await engine.validate(ArchiveData(item.name, bytes));
      } catch (e) {
        result = ValidateResult(name: item.name, valid: false, error: '$e');
      }
      outcomes.add(ValidateOutcome(item: item, result: result));
    }
    onProgress?.call(outcomes.length, total, 'Done');
    return outcomes;
  }
}
