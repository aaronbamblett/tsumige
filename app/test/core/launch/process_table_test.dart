// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vnl/src/core/launch/process_table.dart';

void writeEnviron(String procRoot, String pid, List<String> entries) {
  final dir = Directory(p.join(procRoot, pid))..createSync(recursive: true);
  final bytes = <int>[];
  for (final entry in entries) {
    bytes.addAll(entry.codeUnits);
    bytes.add(0);
  }
  File(p.join(dir.path, 'environ')).writeAsBytesSync(bytes);
}

void main() {
  late Directory proc;
  setUp(() {
    proc = Directory.systemTemp.createTempSync('vnl_proc_test_');
  });
  tearDown(() {
    proc.deleteSync(recursive: true);
  });

  test('finds the pid whose environ holds SteamAppId=<id>', () async {
    writeEnviron(proc.path, '123', ['FOO=1', 'SteamAppId=999']);
    writeEnviron(proc.path, '456', ['FOO=1']);
    writeEnviron(proc.path, '777', ['SteamAppId=9999']);
    Directory(p.join(proc.path, 'self')).createSync();
    Directory(p.join(proc.path, '789')).createSync();
    final table = ProcProcessTable(procRoot: proc.path);
    expect(await table.pidsWithEnv('SteamAppId', '999'), [123]);
  });

  test('a missing proc root finds nothing', () async {
    final table = ProcProcessTable(
        procRoot: p.join(proc.path, 'does-not-exist'));
    expect(await table.pidsWithEnv('SteamAppId', '999'), isEmpty);
  });
}
