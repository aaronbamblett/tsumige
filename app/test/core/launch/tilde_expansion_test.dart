// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:vnl/src/core/launch/launch_command.dart';
import 'package:vnl/src/core/model.dart';

const defaults = LaunchDefaults(
  mode: LaunchMode.proton,
  prefix: '/defaults/prefix',
  runner: '/defaults/proton',
  locale: 'ja_JP.UTF-8',
  umuGameId: 'umu-default',
);

const homeEnv = {'HOME': '/home/aaron'};

void main() {
  test('a ~/ executable expands with HOME', () {
    final game = Game(
      id: 'g1',
      launch: LaunchOverrides(
        mode: LaunchMode.native,
        executable: '~/Games/subahibi/game.sh',
      ),
    );
    final command = buildLaunchCommand(game, defaults, hostEnv: homeEnv);
    expect(command.executable, '/home/aaron/Games/subahibi/game.sh');
    expect(command.workingDirectory, '/home/aaron/Games/subahibi');
  });

  test('a ~/ prefix expands with HOME', () {
    final game = Game(
      id: 'g1',
      launch: LaunchOverrides(
        mode: LaunchMode.wine,
        executable: '/games/subahibi/game.exe',
      ),
    );
    const tildeDefaults = LaunchDefaults(
      mode: LaunchMode.wine,
      prefix: '~/Games/vnl/prefix',
      locale: '',
      umuGameId: 'umu-default',
    );
    final command = buildLaunchCommand(game, tildeDefaults, hostEnv: homeEnv);
    expect(command.env['WINEPREFIX'], '/home/aaron/Games/vnl/prefix');
  });

  test('a ~/ runner expands with HOME', () {
    final game = Game(
      id: 'g1',
      launch: LaunchOverrides(
        mode: LaunchMode.proton,
        executable: '/games/subahibi/game.exe',
        runner: '~/runners/proton-ge',
      ),
    );
    final command = buildLaunchCommand(
      game,
      defaults,
      hostEnv: homeEnv,
      umuRunPath: '/usr/bin/umu-run',
    );
    expect(command.env['PROTONPATH'], '/home/aaron/runners/proton-ge');
  });

  test('an override exe with ~/ expands with HOME', () {
    final game = Game(
      id: 'g1',
      launch: LaunchOverrides(mode: LaunchMode.wine),
    );
    final command = buildLaunchCommand(
      game,
      defaults,
      overrideExe: '~/Games/subahibi/patch.exe',
      hostEnv: homeEnv,
    );
    expect(command.args.first, '/home/aaron/Games/subahibi/patch.exe');
    expect(command.workingDirectory, '/home/aaron/Games/subahibi');
  });

  test('paths without ~/ are left alone', () {
    final game = Game(
      id: 'g1',
      launch: LaunchOverrides(
        mode: LaunchMode.native,
        executable: '/games/subahibi/game.sh',
      ),
    );
    final command = buildLaunchCommand(game, defaults, hostEnv: homeEnv);
    expect(command.executable, '/games/subahibi/game.sh');
    expect(expandTilde('~other/file', homeEnv), '~other/file');
  });

  test('~/ without a HOME is left alone', () {
    expect(
      expandTilde('~/Games/x', const {}),
      '~/Games/x',
    );
  });
}
