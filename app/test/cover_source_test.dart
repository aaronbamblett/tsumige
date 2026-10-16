// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vnl/src/core/covers.dart';
import 'package:vnl/src/core/model.dart';
import 'package:vnl/src/core/paths.dart';
import 'package:vnl/src/features/library/domain/cover_source.dart';

void main() {
  late Directory temp;
  late DataDir dir;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('vnl_cover_source_test_');
    dir = DataDir(temp.path);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Game gameWithCover() => Game(id: 'g1', title: 'G', cover: 'g1.jpg');

  void writeFiles({bool with256 = true, bool with512 = true}) {
    if (with256) {
      File(thumbPath(dir, 'g1', 256))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1]);
    }
    if (with512) {
      File(thumbPath(dir, 'g1', 512))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1]);
    }
    File(p.join(dir.coversOriginal.path, 'g1.jpg'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1]);
  }

  bool exists(String path) => File(path).existsSync();

  test('settled 192 picks the 256 thumbnail', () {
    writeFiles();
    final source = coverSourceFor(gameWithCover(), dir, 192, exists);
    expect(source, isNotNull);
    expect(source!.path, thumbPath(dir, 'g1', 256));
    expect(source.isThumbnail, isTrue);
  });

  test('settled 300 picks the 512 thumbnail', () {
    writeFiles();
    final source = coverSourceFor(gameWithCover(), dir, 300, exists);
    expect(source!.path, thumbPath(dir, 'g1', 512));
    expect(source.isThumbnail, isTrue);
  });

  test('settled 600 picks the original', () {
    writeFiles();
    final source = coverSourceFor(gameWithCover(), dir, 600, exists);
    expect(source!.path.endsWith('g1.jpg'), isTrue);
    expect(source.isThumbnail, isFalse);
  });

  test('missing 256 falls through to 512', () {
    writeFiles(with256: false);
    final source = coverSourceFor(gameWithCover(), dir, 192, exists);
    expect(source!.path, thumbPath(dir, 'g1', 512));
  });

  test('no cover gives null', () {
    writeFiles();
    expect(coverSourceFor(Game(id: 'g1'), dir, 192, exists), isNull);
  });
}
