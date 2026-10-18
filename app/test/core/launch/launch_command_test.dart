// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumige/src/core/launch/launch_command.dart';
import 'package:tsumige/src/core/model.dart';

const defaults = LaunchDefaults(
  prefix: '/defaults/prefix',
  runner: '/defaults/proton',
  locale: 'ja_JP.UTF-8',
  umuGameId: 'umu-default',
);

Game gameWith(LaunchOverrides launch) =>
    Game(id: 'game-1', title: 'Subahibi', launch: launch);

LaunchCommand build(Game game,
        {String? overrideExe,
        Map<String, String> hostEnv = const {},
        String? umuRunPath = '/usr/bin/umu-run'}) =>
    buildLaunchCommand(game, defaults,
        overrideExe: overrideExe, hostEnv: hostEnv, umuRunPath: umuRunPath);

void main() {
  test('proton builds the exact command', () {
    final game = gameWith(LaunchOverrides(
      mode: LaunchMode.proton,
      executable: '/games/suba/game.exe',
      arguments: '--fullscreen "data dir"',
      environment: 'EXTRA=yes',
    ));
    expect(
      build(game),
      LaunchCommand(
        executable: '/usr/bin/umu-run',
        args: ['/games/suba/game.exe', '--fullscreen', 'data dir'],
        env: {
          'WINEPREFIX': '/defaults/prefix',
          'GAMEID': 'umu-default',
          'PROTONPATH': '/defaults/proton',
          'LANG': 'ja_JP.UTF-8',
          'LC_ALL': 'ja_JP.UTF-8',
          'EXTRA': 'yes',
        },
        workingDirectory: '/games/suba',
      ),
    );
  });

  test('wine builds the exact command', () {
    final game = gameWith(LaunchOverrides(
      mode: LaunchMode.wine,
      executable: '/games/suba/game.exe',
      runner: '/opt/wine-ge/bin/wine',
      prefix: '/games/suba/prefix',
      locale: 'zh_CN.UTF-8',
      arguments: '-a b',
      environment: 'EXTRA=yes',
    ));
    expect(
      build(game),
      LaunchCommand(
        executable: '/opt/wine-ge/bin/wine',
        args: ['/games/suba/game.exe', '-a', 'b'],
        env: {
          'WINEPREFIX': '/games/suba/prefix',
          'LANG': 'zh_CN.UTF-8',
          'LC_ALL': 'zh_CN.UTF-8',
          'EXTRA': 'yes',
        },
        workingDirectory: '/games/suba',
      ),
    );
  });

  test('wine without any runner falls back to wine', () {
    final game = gameWith(LaunchOverrides(
      mode: LaunchMode.wine,
      executable: '/games/suba/game.exe',
    ));
    final command = buildLaunchCommand(
      game,
      const LaunchDefaults(
          prefix: '/p',
          locale: '',
          umuGameId: 'umu-default'),
      hostEnv: const {},
    );
    expect(command.executable, 'wine');
    expect(command.args, ['/games/suba/game.exe']);
    expect(command.env, {'WINEPREFIX': '/p'});
  });

  test('native builds the exact command', () {
    final game = gameWith(LaunchOverrides(
      mode: LaunchMode.native,
      executable: '/games/suba/start.sh',
      arguments: '--fullscreen',
      environment: 'EXTRA=yes',
    ));
    expect(
      build(game),
      const LaunchCommand(
        executable: '/games/suba/start.sh',
        args: ['--fullscreen'],
        env: {'EXTRA': 'yes'},
        workingDirectory: '/games/suba',
      ),
    );
  });

  test('steam builds the exact command', () {
    final game = gameWith(LaunchOverrides(
      mode: LaunchMode.steam,
      steamAppId: 12345,
      environment: 'EXTRA=yes',
    ));
    expect(
      build(game),
      const LaunchCommand(
        executable: 'steam',
        args: ['-applaunch', '12345'],
        env: {'EXTRA': 'yes'},
        workingDirectory: null,
      ),
    );
  });

  test('game overrides beat the defaults for every field', () {
    final game = gameWith(LaunchOverrides(
      mode: LaunchMode.wine,
      executable: '/games/other/game.exe',
      runner: '/games/other/wine',
      prefix: '/games/other/prefix',
      locale: 'ko_KR.UTF-8',
      umuGameId: 'umu-other',
      arguments: '--other',
      environment: 'OTHER=1',
    ));
    final command = buildLaunchCommand(
      game,
      const LaunchDefaults(
        prefix: '/defaults/prefix',
        runner: '/defaults/proton',
        locale: 'ja_JP.UTF-8',
        umuGameId: 'umu-default',
      ),
      hostEnv: const {},
    );
    expect(command.executable, '/games/other/wine');
    expect(command.args, ['/games/other/game.exe', '--other']);
    expect(
      command.env,
      {
        'WINEPREFIX': '/games/other/prefix',
        'LANG': 'ko_KR.UTF-8',
        'LC_ALL': 'ko_KR.UTF-8',
        'OTHER': '1',
      },
    );
    expect(command.workingDirectory, '/games/other');
  });

  test('a null runner leaves PROTONPATH out', () {
    final game = gameWith(LaunchOverrides(
      executable: '/games/suba/game.exe',
    ));
    final command = buildLaunchCommand(
      game,
      const LaunchDefaults(
          prefix: '/p',
          locale: 'ja_JP.UTF-8',
          umuGameId: 'umu-default'),
      hostEnv: const {},
      umuRunPath: '/usr/bin/umu-run',
    );
    expect(command.env.containsKey('PROTONPATH'), isFalse);
    expect(command.env['GAMEID'], 'umu-default');
  });

  test('an empty locale leaves LANG and LC_ALL out', () {
    final game = gameWith(LaunchOverrides(
      executable: '/games/suba/game.exe',
      locale: '',
    ));
    final command = buildLaunchCommand(
      game,
      const LaunchDefaults(
          prefix: '/p',
          runner: '/proton',
          locale: '',
          umuGameId: 'umu-default'),
      hostEnv: const {},
      umuRunPath: '/usr/bin/umu-run',
    );
    expect(command.env.containsKey('LANG'), isFalse);
    expect(command.env.containsKey('LC_ALL'), isFalse);
  });

  test('the game environment overrides the generated variables', () {
    final game = gameWith(LaunchOverrides(
      executable: '/games/suba/game.exe',
      environment: 'WINEPREFIX=/custom\nGAMEID=umu-custom',
    ));
    final command = build(game);
    expect(command.env['WINEPREFIX'], '/custom');
    expect(command.env['GAMEID'], 'umu-custom');
  });

  test('overrideExe runs another exe through the same mode and prefix', () {
    final game = gameWith(LaunchOverrides(mode: LaunchMode.proton));
    final command = build(game, overrideExe: '/games/suba/patcher.exe');
    expect(command.executable, '/usr/bin/umu-run');
    expect(command.args.first, '/games/suba/patcher.exe');
    expect(command.env['WINEPREFIX'], '/defaults/prefix');
    expect(command.workingDirectory, '/games/suba');
  });

  test('overrideExe with wine uses the wine runner', () {
    final game = gameWith(LaunchOverrides(mode: LaunchMode.wine));
    final command = build(game, overrideExe: '/games/suba/setup.exe');
    expect(command.executable, '/defaults/proton');
    expect(command.args.first, '/games/suba/setup.exe');
    expect(command.workingDirectory, '/games/suba');
  });

  test('overrideExe with steam is rejected', () {
    final game = gameWith(LaunchOverrides(
      mode: LaunchMode.steam,
      steamAppId: 12345,
    ));
    expect(
      () => build(game, overrideExe: '/games/suba/patcher.exe'),
      throwsA(isA<LaunchConfigError>().having((e) => e.message, 'message',
          'Run .exe inside prefix needs Proton or Wine')),
    );
  });

  test('overrideExe with native is rejected', () {
    final game = gameWith(LaunchOverrides(
      mode: LaunchMode.native,
      executable: '/games/suba/start.sh',
    ));
    expect(
      () => build(game, overrideExe: '/games/suba/other.sh'),
      throwsA(isA<LaunchConfigError>().having((e) => e.message, 'message',
          'Run .exe inside prefix needs Proton or Wine')),
    );
  });

  test('a missing executable is rejected', () {
    final game = gameWith(LaunchOverrides(mode: LaunchMode.wine));
    expect(
      () => build(game),
      throwsA(isA<LaunchConfigError>()
          .having((e) => e.message, 'message', 'No executable set')),
    );
  });

  test('proton without umu-run is rejected', () {
    final game = gameWith(LaunchOverrides(
      executable: '/games/suba/game.exe',
    ));
    expect(
      () => buildLaunchCommand(game, defaults,
          hostEnv: const {}, umuRunPath: null),
      throwsA(isA<LaunchConfigError>().having(
          (e) => e.message, 'message', 'umu-run not found on PATH')),
    );
  });

  test('steam without an app id is rejected', () {
    final game = gameWith(LaunchOverrides(mode: LaunchMode.steam));
    expect(
      () => build(game),
      throwsA(isA<LaunchConfigError>()
          .having((e) => e.message, 'message', 'Steam App ID is not set')),
    );
  });

  test('flatpak wraps the command with display and directory', () {
    final game = gameWith(LaunchOverrides(
      mode: LaunchMode.wine,
      executable: '/games/suba/game.exe',
      arguments: '--fullscreen',
      environment: 'EXTRA=yes',
    ));
    final command = build(game, hostEnv: const {
      'FLATPAK_ID': 'com.example.Tsumige',
      'DISPLAY': ':0',
    });
    expect(
      command,
      const LaunchCommand(
        executable: 'flatpak-spawn',
        args: [
          '--host',
          '--env=DISPLAY=:0',
          '--directory=/games/suba',
          '--env=WINEPREFIX=/defaults/prefix',
          '--env=LANG=ja_JP.UTF-8',
          '--env=LC_ALL=ja_JP.UTF-8',
          '--env=EXTRA=yes',
          '/defaults/proton',
          '/games/suba/game.exe',
          '--fullscreen',
        ],
        env: {},
        workingDirectory: null,
      ),
    );
  });

  test('flatpak without DISPLAY leaves it out', () {
    final game = gameWith(LaunchOverrides(
      mode: LaunchMode.native,
      executable: '/games/suba/start.sh',
    ));
    final command =
        build(game, hostEnv: const {'FLATPAK_ID': 'com.example.Tsumige'});
    expect(command.executable, 'flatpak-spawn');
    expect(
      command.args,
      [
        '--host',
        '--directory=/games/suba',
        '/games/suba/start.sh',
      ],
    );
    expect(command.env, isEmpty);
    expect(command.workingDirectory, isNull);
  });

  test('flatpak proton wraps the host umu-run', () {
    final game = gameWith(LaunchOverrides(
      executable: '/games/suba/game.exe',
    ));
    final command = build(game, hostEnv: const {
      'FLATPAK_ID': 'com.example.Tsumige',
      'DISPLAY': ':0',
    });
    expect(command.executable, 'flatpak-spawn');
    expect(command.args, contains('umu-run'));
    expect(command.args.last, '/games/suba/game.exe');
  });

  test('findOnPath returns the first match with an injected checker', () {
    final seen = <String>[];
    bool checker(String path) {
      seen.add(path);
      return path == '/opt/bin/umu-run';
    }

    final found = findOnPath('umu-run',
        const {'PATH': '/usr/bin:/opt/bin:/usr/local/bin'},
        isExecutable: checker);
    expect(found, '/opt/bin/umu-run');
    expect(seen, ['/usr/bin/umu-run', '/opt/bin/umu-run']);
  });

  test('findOnPath returns null when nothing matches', () {
    expect(
        findOnPath('umu-run', const {'PATH': '/usr/bin'},
            isExecutable: (_) => false),
        isNull);
    expect(findOnPath('umu-run', const {}), isNull);
  });

  test('launch commands compare by value', () {
    const a = LaunchCommand(
        executable: 'wine', args: ['x'], env: {'K': 'V'}, workingDirectory: '/g');
    const b = LaunchCommand(
        executable: 'wine', args: ['x'], env: {'K': 'V'}, workingDirectory: '/g');
    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
    expect(
        a,
        isNot(const LaunchCommand(
            executable: 'wine',
            args: ['y'],
            env: {'K': 'V'},
            workingDirectory: '/g')));
  });
}
