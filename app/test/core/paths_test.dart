// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tsumige/src/core/host_platform.dart';
import 'package:tsumige/src/core/paths.dart';

const _linux = HostPlatform(HostOs.linux);
const _macos = HostPlatform(HostOs.macos);
const _windows = HostPlatform(HostOs.windows);

void main() {
  test('Linux keeps the XDG data folder', () {
    expect(
      DataDir.resolve({'HOME': '/home/v'}, platform: _linux).root,
      '/home/v/.local/share/tsumige',
    );
    expect(
      DataDir.resolve({
        'HOME': '/home/v',
        'XDG_DATA_HOME': '/data',
      }, platform: _linux).root,
      '/data/tsumige',
    );
  });

  test('macOS uses Application Support', () {
    expect(
      DataDir.resolve({'HOME': '/Users/v'}, platform: _macos).root,
      '/Users/v/Library/Application Support/Tsumige',
    );
  });

  test('Windows uses APPDATA with Windows separators', () {
    expect(
      DataDir.resolve({
        'APPDATA': r'C:\Users\v\AppData\Roaming',
      }, platform: _windows).root,
      r'C:\Users\v\AppData\Roaming\Tsumige',
    );
  });

  test('realPath resolves a symlinked directory', () {
    final temp = Directory.systemTemp.createTempSync('tsumige_realpath_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final real = Directory(p.join(temp.path, 'real'))..createSync();
    File(p.join(real.path, 'game.exe')).writeAsBytesSync([0]);
    Link(p.join(temp.path, 'link')).createSync(real.path);
    expect(
      realPath(p.join(temp.path, 'link', 'game.exe')),
      p.join(real.path, 'game.exe'),
    );
  });

  test('realPath resolves the existing part of a missing file', () {
    final temp = Directory.systemTemp.createTempSync('tsumige_realpath_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final real = Directory(p.join(temp.path, 'real'))..createSync();
    Link(p.join(temp.path, 'link')).createSync(real.path);
    expect(
      realPath(p.join(temp.path, 'link', 'New', 'game.exe')),
      p.join(real.path, 'New', 'game.exe'),
    );
  });

  test('TSUMIGE_DATA_DIR overrides on every platform', () {
    for (final platform in [_linux, _macos, _windows]) {
      expect(
        DataDir.resolve({
          'TSUMIGE_DATA_DIR': '/custom',
          'HOME': '/Users/v',
          'APPDATA': r'C:\x',
        }, platform: platform).root,
        '/custom',
        reason: platform.name,
      );
    }
  });
}
