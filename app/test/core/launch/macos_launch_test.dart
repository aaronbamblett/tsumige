// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumige/src/core/host_platform.dart';
import 'package:tsumige/src/core/launch/launch_command.dart';
import 'package:tsumige/src/core/model.dart';

const _macos = HostPlatform(HostOs.macos);

const _defaults = LaunchDefaults(
  prefix: '/p',
  locale: '',
  umuGameId: 'umu-default',
);

LaunchCommand _build(LaunchOverrides launch) => buildLaunchCommand(
  Game(id: 'g1', title: 'Subahibi', launch: launch),
  _defaults,
  hostEnv: const {},
  platform: _macos,
);

void main() {
  test('an .app bundle opens through open -W -n with its arguments', () {
    final command = _build(
      LaunchOverrides(
        mode: LaunchMode.native,
        executable: '/Applications/Subahibi.app',
        arguments: '--fullscreen "save slot"',
      ),
    );
    expect(
      command,
      const LaunchCommand(
        executable: 'open',
        args: [
          '-W',
          '-n',
          '/Applications/Subahibi.app',
          '--args',
          '--fullscreen',
          'save slot',
        ],
        env: {},
        workingDirectory: null,
      ),
    );
  });

  test('a plain binary runs directly from its folder', () {
    final command = _build(
      LaunchOverrides(
        mode: LaunchMode.native,
        executable: '/Users/v/Games/suba/game',
        arguments: '--windowed',
      ),
    );
    expect(
      command,
      const LaunchCommand(
        executable: '/Users/v/Games/suba/game',
        args: ['--windowed'],
        env: {},
        workingDirectory: '/Users/v/Games/suba',
      ),
    );
  });

  test('a game with no saved mode runs as native on macOS', () {
    final command = _build(LaunchOverrides(
      executable: '/Applications/Subahibi.app',
    ));
    expect(command.executable, 'open');
    expect(command.args.take(3), ['-W', '-n', '/Applications/Subahibi.app']);
  });

  test('a Steam game opens its steam:// link with no session', () {
    final command = _build(
      LaunchOverrides(mode: LaunchMode.steam, steamAppId: 4242),
    );
    expect(
      command,
      const LaunchCommand(
        executable: 'open',
        args: ['steam://rungameid/4242'],
        env: {},
        workingDirectory: null,
      ),
    );
  });

  test('a .app path is run directly on Linux', () {
    final command = buildLaunchCommand(
      Game(
        id: 'g1',
        title: 'Subahibi',
        launch: LaunchOverrides(
          mode: LaunchMode.native,
          executable: '/games/Subahibi.app',
        ),
      ),
      _defaults,
      hostEnv: const {},
      platform: const HostPlatform(HostOs.linux),
    );
    expect(command.executable, '/games/Subahibi.app');
    expect(command.args, isEmpty);
  });
}
