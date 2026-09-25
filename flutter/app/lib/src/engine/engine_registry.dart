import 'dart_engine.dart';
import 'engine.dart';

/// Rebuilds an engine implementation from its [CbzEngine.id].
///
/// Services that hand CPU-bound work to `Isolate.run` cannot send the engine
/// instance across the boundary; they send the id instead and the isolate calls
/// this factory, so the engine chosen in `cbzEngineProvider` stays the single
/// place where the backend is picked. Add a case here when a new backend lands
/// (for example the optional Rust engine from `flutter/TARGET.md`).
CbzEngine engineFromId(String id) {
  switch (id) {
    case DartCbzEngine.engineId:
      return const DartCbzEngine();
    default:
      throw ArgumentError.value(id, 'id', 'Unknown engine implementation');
  }
}
