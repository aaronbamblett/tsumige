// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../model.dart';
import '../paths.dart';

/// Timestamp prefix for launch logs: `<yyyyMMdd-HHmmss>`.
String launchTimestamp(DateTime nowUtc) {
  final u = nowUtc.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}-'
      '${two(u.hour)}${two(u.minute)}${two(u.second)}';
}

/// Makes a title safe for a log file name: the first 48 characters, ASCII
/// alphanumerics kept, every other run collapsed to one `-`.
String safeLogTitle(String title) {
  final head = title.length <= 48 ? title : title.substring(0, 48);
  final buf = StringBuffer();
  var lastDash = true;
  for (final unit in head.codeUnits) {
    final alnum = (unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x5A) ||
        (unit >= 0x61 && unit <= 0x7A);
    if (alnum) {
      buf.writeCharCode(unit);
      lastDash = false;
    } else if (!lastDash) {
      buf.write('-');
      lastDash = true;
    }
  }
  var safe = buf.toString();
  if (safe.endsWith('-')) safe = safe.substring(0, safe.length - 1);
  return safe.isEmpty ? 'game' : safe;
}

/// Creates `logs/<yyyyMMdd-HHmmss>-<safe title>.log` and returns it,
/// creating `logs/` when it is missing.
File newLaunchLog(DataDir dir, Game game, DateTime nowUtc) {
  dir.logs.createSync(recursive: true);
  final name = '${launchTimestamp(nowUtc)}-${safeLogTitle(game.title)}.log';
  final log = File(p.join(dir.logs.path, name));
  log.createSync();
  return log;
}

/// Copies a finished launch log to `logs/latest.log`.
Future<void> updateLatestLog(DataDir dir, File log) async {
  await dir.logs.create(recursive: true);
  await log.copy(p.join(dir.logs.path, 'latest.log'));
}
