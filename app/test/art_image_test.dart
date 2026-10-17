// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tsumige/src/features/library/domain/cover_source.dart';
import 'package:tsumige/src/features/library/presentation/widgets/art_image.dart';

void main() {
  test('a file rewritten at the same path gets a new image key', () {
    final temp = Directory.systemTemp.createTempSync('tsumige_art_image_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File(p.join(temp.path, 'g1.jpg'))
      ..writeAsBytesSync([1, 2, 3]);
    final before = artFileImage(
      file,
      version: artVersionOf(file.path),
      cacheWidth: 512,
    );
    expect(
      artFileImage(file, version: artVersionOf(file.path), cacheWidth: 512),
      before,
    );
    file.writeAsBytesSync([1, 2, 3, 4, 5]);
    expect(
      artFileImage(file, version: artVersionOf(file.path), cacheWidth: 512),
      isNot(before),
    );
  });
}
