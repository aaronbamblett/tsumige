// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:path/path.dart' as p;

/// Finds game processes by environment, so a Steam launch times the game
/// instead of the `steam -applaunch` wrapper that exits at once.
abstract class ProcessTable {
  Future<List<int>> pidsWithEnv(String key, String value);
}

/// Reads `/proc/<pid>/environ` (NUL-separated), skipping unreadable entries.
class ProcProcessTable implements ProcessTable {
  ProcProcessTable({this.procRoot = '/proc'});

  final String procRoot;

  @override
  Future<List<int>> pidsWithEnv(String key, String value) async {
    final needle = '$key=$value';
    final found = <int>[];
    List<FileSystemEntity> entries;
    try {
      entries = await Directory(procRoot).list(followLinks: false).toList();
    } catch (_) {
      return found;
    }
    for (final entry in entries) {
      if (int.tryParse(p.basename(entry.path)) == null) continue;
      try {
        final bytes =
            await File(p.join(entry.path, 'environ')).readAsBytes();
        if (_environHas(bytes, needle)) {
          found.add(int.parse(p.basename(entry.path)));
        }
      } catch (_) {
        continue;
      }
    }
    return found;
  }
}

bool _environHas(List<int> bytes, String needle) {
  final want = needle.codeUnits;
  var start = 0;
  for (var i = 0; i <= bytes.length; i++) {
    if (i == bytes.length || bytes[i] == 0) {
      if (i - start == want.length) {
        var match = true;
        for (var j = 0; j < want.length; j++) {
          if (bytes[start + j] != want[j]) {
            match = false;
            break;
          }
        }
        if (match) return true;
      }
      start = i + 1;
    }
  }
  return false;
}
