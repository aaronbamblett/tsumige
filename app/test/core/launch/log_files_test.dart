// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tsumige/src/core/launch/log_files.dart';
import 'package:tsumige/src/core/model.dart';
import 'package:tsumige/src/core/paths.dart';

void main() {
  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('tsumige_log_test_');
  });
  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  test('newLaunchLog names the file by UTC time and safe title', () {
    final dir = DataDir(temp.path);
    final game = Game(id: 'g1', title: 'Subahibi');
    final log =
        newLaunchLog(dir, game, DateTime.utc(2026, 10, 17, 12, 5, 30));
    expect(log.path, p.join(temp.path, 'logs', '20261017-120530-Subahibi.log'));
    expect(Directory(p.join(temp.path, 'logs')).existsSync(), isTrue);
  });

  test('unsafe characters become single dashes', () {
    expect(safeLogTitle('A: Messy/Title?!'), 'A-Messy-Title');
    expect(safeLogTitle('a  b'), 'a-b');
    expect(safeLogTitle(' -hi- '), 'hi');
  });

  test('only the first 48 characters are kept', () {
    final title = '${'a' * 60}.exe';
    expect(safeLogTitle(title), 'a' * 48);
  });

  test('a title with nothing safe falls back to game', () {
    expect(safeLogTitle('???'), 'game');
    expect(safeLogTitle('あいうえお'), 'game');
    expect(safeLogTitle(''), 'game');
  });

  test('updateLatestLog copies the log to latest.log', () async {
    final dir = DataDir(temp.path);
    final game = Game(id: 'g1', title: 'Subahibi');
    final log =
        newLaunchLog(dir, game, DateTime.utc(2026, 10, 17, 12, 5, 30));
    await log.writeAsString('line one\nline two\n');
    await updateLatestLog(dir, log);
    final latest = File(p.join(temp.path, 'logs', 'latest.log'));
    expect(await latest.readAsString(), 'line one\nline two\n');
  });
}
