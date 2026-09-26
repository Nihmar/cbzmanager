import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set of selected archive paths (empty = no selection mode).
class SelectionController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  void toggle(String path) {
    final next = <String>{...state};
    if (!next.remove(path)) next.add(path);
    state = next;
  }

  void select(Iterable<String> paths) => state = paths.toSet();

  void clear() => state = const <String>{};
}

final selectionProvider = NotifierProvider<SelectionController, Set<String>>(
  SelectionController.new,
);
