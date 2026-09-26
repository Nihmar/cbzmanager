import 'dart:io';

/// Number of online CPUs, used for the automatic worker-pool size.
///
/// Mirrors `OnlineCpuCount`: never below 1. On platforms where
/// `Platform.numberOfProcessors` is unreliable this is only a heuristic.
int onlineCpuCount() {
  final n = Platform.numberOfProcessors;
  return n < 1 ? 1 : n;
}
