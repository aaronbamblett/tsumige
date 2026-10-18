// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumige/src/features/library/domain/drop_routing.dart';

bool _isDir(String path) => !path.endsWith('.exe');

void main() {
  test('nothing dropped routes nowhere', () {
    expect(routeDrop(const [], isDirectory: _isDir), isNull);
  });

  test('one folder is a single game with that folder', () {
    final route = routeDrop(['/games/Alpha'], isDirectory: _isDir);
    expect(route, isA<DropMatch>());
    final match = route! as DropMatch;
    expect(match.folder, '/games/Alpha');
    expect(match.file, isNull);
  });

  test('one game file matches its parent folder with that file', () {
    final match =
        routeDrop(['/games/Alpha/Alpha.exe'], isDirectory: _isDir)!
            as DropMatch;
    expect(match.folder, '/games/Alpha');
    expect(match.file, '/games/Alpha/Alpha.exe');
  });

  test('several folders import with those folders as the roots', () {
    final route =
        routeDrop(['/games/Alpha', '/games/Beta'], isDirectory: _isDir)!
            as DropImport;
    expect(route.roots, ['/games/Alpha', '/games/Beta']);
  });

  test('several items import their folders, a file counting as its parent', () {
    final route =
        routeDrop([
              '/games/Alpha',
              '/games/Beta/Beta.exe',
              '/games/Beta/Beta.exe',
            ], isDirectory: _isDir)!
            as DropImport;
    expect(route.roots, ['/games/Alpha', '/games/Beta']);
  });
}
