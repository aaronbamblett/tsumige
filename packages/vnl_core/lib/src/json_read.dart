// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

String readString(Map m, String k, [String d = '']) {
  final v = m[k];
  return v is String ? v : d;
}

String? readStringOrNull(Map m, String k) {
  final v = m[k];
  return v is String ? v : null;
}

bool readBool(Map m, String k, [bool d = false]) {
  final v = m[k];
  return v is bool ? v : d;
}

int? readIntOrNull(Map m, String k) {
  final v = m[k];
  return v is int ? v : null;
}

double? readDoubleOrNull(Map m, String k) {
  final v = m[k];
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return null;
}

List<String> readStringList(Map m, String k, [List<String> d = const []]) {
  final v = m[k];
  if (v is! List) return d;
  return v.whereType<String>().toList();
}

DateTime? readDateOrNull(Map m, String k) {
  final v = m[k];
  if (v is! String) return null;
  try {
    return DateTime.parse(v);
  } on FormatException {
    return null;
  }
}

List<T> readList<T>(Map m, String k, T? Function(Object?) each) {
  final v = m[k];
  if (v is! List) return [];
  final out = <T>[];
  for (final e in v) {
    try {
      final parsed = each(e);
      if (parsed != null) out.add(parsed);
    } catch (_) {
      continue;
    }
  }
  return out;
}
