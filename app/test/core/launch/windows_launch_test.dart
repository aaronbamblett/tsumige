// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumige/src/core/host_platform.dart';
import 'package:tsumige/src/core/launch/launch_command.dart';
import 'package:tsumige/src/core/model.dart';

const _windows = HostPlatform(HostOs.windows);

const _defaults = LaunchDefaults(
  prefix: '/p',
  locale: '',
  umuGameId: 'umu-default',
);

LaunchCommand _build(LaunchOverrides launch) => buildLaunchCommand(
      Game(id: 'g1', title: 'Subahibi', launch: launch),
      _defaults,
      hostEnv: const {},
      platform: _windows,
    );

void main() {
  test('a native exe runs directly from its folder', () {
    final command = _build(LaunchOverrides(
      mode: LaunchMode.native,
      executable: r'C:\Games\Subahibi\game.exe',
      arguments: '--windowed',
    ));
    expect(
      command,
      const LaunchCommand(
        executable: r'C:\Games\Subahibi\game.exe',
        args: ['--windowed'],
        env: {},
        workingDirectory: r'C:\Games\Subahibi',
      ),
    );
  });

  test('a Steam game is launched through explorer with its steam:// link', () {
    final command = _build(LaunchOverrides(
      mode: LaunchMode.steam,
      steamAppId: 4242,
    ));
    expect(
      command,
      const LaunchCommand(
        executable: 'explorer.exe',
        args: ['steam://rungameid/4242'],
        env: {},
        workingDirectory: null,
      ),
    );
  });

  test('findOnPath splits PATH on semicolons and tries PATHEXT', () {
    final checked = <String>[];
    final found = findOnPath(
      'umu-run',
      const {
        'PATH': r'C:\Tools;C:\Bin',
        'PATHEXT': '.COM;.EXE;.BAT',
      },
      platform: _windows,
      isExecutable: (path) {
        checked.add(path);
        return path == r'C:\Bin\umu-run.EXE';
      },
    );
    expect(found, r'C:\Bin\umu-run.EXE');
    expect(checked, [
      r'C:\Tools\umu-run.COM',
      r'C:\Tools\umu-run.EXE',
      r'C:\Tools\umu-run.BAT',
      r'C:\Bin\umu-run.COM',
      r'C:\Bin\umu-run.EXE',
    ]);
  });

  test('findOnPath tries the bare name first when it already has a PATHEXT '
      'extension', () {
    final checked = <String>[];
    final found = findOnPath(
      'umu-run.exe',
      const {'PATH': r'C:\Bin', 'PATHEXT': '.COM;.EXE'},
      platform: _windows,
      isExecutable: (path) {
        checked.add(path);
        return path == r'C:\Bin\umu-run.exe';
      },
    );
    expect(found, r'C:\Bin\umu-run.exe');
    expect(checked.first, r'C:\Bin\umu-run.exe');
  });

  test('findOnPath appends PATHEXT to a name without an extension', () {
    final checked = <String>[];
    findOnPath(
      'umu-run',
      const {'PATH': r'C:\Bin', 'PATHEXT': '.COM;.EXE'},
      platform: _windows,
      isExecutable: (path) {
        checked.add(path);
        return false;
      },
    );
    expect(checked, [r'C:\Bin\umu-run.COM', r'C:\Bin\umu-run.EXE']);
  });

  test('findOnPath uses the default PATHEXT when none is set', () {
    final found = findOnPath(
      'tool',
      const {'PATH': r'C:\Bin'},
      platform: _windows,
      isExecutable: (path) => path == r'C:\Bin\tool.CMD',
    );
    expect(found, r'C:\Bin\tool.CMD');
  });

  test('findOnPath on Windows ignores colons in PATH', () {
    final found = findOnPath(
      'tool',
      const {'PATH': r'C:\Bin:C:\Other', 'PATHEXT': '.EXE'},
      platform: _windows,
      isExecutable: (path) => path == r'C:\Other\tool.EXE',
    );
    expect(found, isNull);
  });
}
