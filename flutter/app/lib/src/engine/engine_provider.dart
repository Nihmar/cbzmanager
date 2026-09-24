import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart_engine.dart';
import 'engine.dart';

/// The active engine implementation. Swapping to a different backend (for
/// example a Rust engine exposed through FFI) only changes this provider.
final cbzEngineProvider = Provider<CbzEngine>((ref) => const DartCbzEngine());
