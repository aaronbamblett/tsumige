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
        final bytes = await File(p.join(entry.path, 'environ')).readAsBytes();
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

/// The sandbox has a private PID namespace, so the scan runs on the host.
class FlatpakHostProcessTable implements ProcessTable {
  FlatpakHostProcessTable([
    Future<ProcessResult> Function(String executable, List<String> args)?
    runner,
  ]) : _runner = runner ?? Process.run;

  final Future<ProcessResult> Function(String executable, List<String> args)
  _runner;

  static const _script = r'grep -lszxF -- "$1=$2" /proc/[0-9]*/environ; exit 0';

  static final _environPath = RegExp(r'^/proc/(\d+)/environ$');

  @override
  Future<List<int>> pidsWithEnv(String key, String value) async {
    try {
      final result = await _runner('flatpak-spawn', [
        '--host',
        'sh',
        '-c',
        _script,
        'scan',
        key,
        value,
      ]);
      if (result.exitCode != 0) return [];
      final found = <int>[];
      for (final line in (result.stdout as String).split('\n')) {
        final match = _environPath.firstMatch(line);
        if (match == null) continue;
        final pid = int.parse(match.group(1)!);
        if (!found.contains(pid)) found.add(pid);
      }
      return found;
    } catch (_) {
      return [];
    }
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
