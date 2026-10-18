// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumige/src/core/host_platform.dart';
import 'package:tsumige/src/core/launch/launch_command.dart';

const _appImage = HostPlatform(HostOs.linux, inAppImage: true);
const _plain = HostPlatform(HostOs.linux);

const _mount = '/tmp/.mount_Tsumi';

void main() {
  final hostEnv = {
    'HOME': '/home/v',
    'DISPLAY': ':0',
    'APPIMAGE': '/home/v/Tsumige.AppImage',
    'APPDIR': _mount,
    'ARGV0': 'tsumige',
    'OWD': '/home/v',
    'LD_LIBRARY_PATH': '$_mount/usr/lib:/usr/lib',
    'LD_PRELOAD': '$_mount/usr/lib/shim.so',
    'PATH': '$_mount/usr/bin:/usr/bin:$_mount:/bin',
    'XDG_DATA_DIRS': '$_mount/usr/share:/usr/share',
    'GSETTINGS_SCHEMA_DIR': '$_mount/usr/share/glib-2.0/schemas',
    'QT_PLUGIN_PATH': '$_mount/usr/plugins',
    'GDK_PIXBUF_MODULE_FILE': '$_mount/loaders.cache',
    'PYTHONPATH': '$_mount/usr/lib/python3',
    'LANG': 'ja_JP.UTF-8',
  };

  test('AppImage variables and entries inside APPDIR are removed', () {
    expect(gameEnvironment(hostEnv, const {}, platform: _appImage), {
      'HOME': '/home/v',
      'DISPLAY': ':0',
      'LD_LIBRARY_PATH': '/usr/lib',
      'PATH': '/usr/bin:/bin',
      'XDG_DATA_DIRS': '/usr/share',
      'LANG': 'ja_JP.UTF-8',
    });
  });

  test('a path variable with nothing left is dropped', () {
    final env = gameEnvironment(
      {
        'APPDIR': _mount,
        'PATH': '$_mount/usr/bin',
        'LD_PRELOAD': '$_mount/usr/lib/shim.so',
      },
      const {},
      platform: _appImage,
    );
    expect(env, isEmpty);
  });

  test('a prefix that only looks like APPDIR is kept', () {
    final env = gameEnvironment(
      {
        'APPDIR': _mount,
        'PATH': '${_mount}2/bin:$_mount/usr/bin',
      },
      const {},
      platform: _appImage,
    );
    expect(env, {'PATH': '${_mount}2/bin'});
  });

  test('the game environment is applied after cleaning', () {
    final env = gameEnvironment(
      hostEnv,
      {
        'PATH': '/games/bin',
        'LD_PRELOAD': '$_mount/game-shim.so',
        'WINEPREFIX': '/prefix',
      },
      platform: _appImage,
    );
    expect(env['PATH'], '/games/bin');
    expect(env['LD_PRELOAD'], '$_mount/game-shim.so');
    expect(env['WINEPREFIX'], '/prefix');
    expect(env.containsKey('APPDIR'), isFalse);
    expect(env['LD_LIBRARY_PATH'], '/usr/lib');
  });

  test('outside an AppImage the host environment passes through unchanged',
      () {
    expect(gameEnvironment(hostEnv, const {}, platform: _plain), hostEnv);
  });
}
