import 'dart:convert';

/// Byte-wise string comparison matching the reference `CompareStr` (and Python
/// `sorted()`), independent of locale collation. Compares UTF-8 bytes.
int compareStr(String a, String b) {
  final ab = utf8.encode(a);
  final bb = utf8.encode(b);
  final n = ab.length < bb.length ? ab.length : bb.length;
  for (var i = 0; i < n; i++) {
    final d = ab[i] - bb[i];
    if (d != 0) return d;
  }
  return ab.length - bb.length;
}
