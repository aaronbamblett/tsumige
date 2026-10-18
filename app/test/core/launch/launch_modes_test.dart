// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumige/src/core/host_platform.dart';
import 'package:tsumige/src/core/launch/launch_command.dart';
import 'package:tsumige/src/core/launch/launch_modes.dart';
import 'package:tsumige/src/core/model.dart';

const _linux = HostPlatform(HostOs.linux);
const _macos = HostPlatform(HostOs.macos);
const _windows = HostPlatform(HostOs.windows);

const _defaults = LaunchDefaults(
  prefix: '/defaults/prefix',
  runner: '/defaults/proton',
  locale: '',
  umuGameId: 'umu-default',
);

void main() {
  test('Linux offers all four modes', () {
    expect(launchModesFor(_linux), LaunchMode.values);
  });

  test('macOS and Windows offer only native and Steam', () {
    expect(launchModesFor(_macos), [LaunchMode.native, LaunchMode.steam]);
    expect(launchModesFor(_windows), [LaunchMode.native, LaunchMode.steam]);
  });

  test('the default mode is Proton on Linux and native elsewhere', () {
    expect(defaultLaunchMode(_linux), LaunchMode.proton);
    expect(defaultLaunchMode(_macos), LaunchMode.native);
    expect(defaultLaunchMode(_windows), LaunchMode.native);
  });

  test('an unavailable mode names the mode and the OS', () {
    expect(
      launchModeUnavailableMessage(LaunchMode.proton, _macos),
      "Proton isn't available on macOS.",
    );
    expect(
      launchModeUnavailableMessage(LaunchMode.wine, _windows),
      "Wine isn't available on Windows.",
    );
  });

  test('an available mode has no message', () {
    expect(launchModeUnavailableMessage(LaunchMode.proton, _linux), isNull);
    expect(launchModeUnavailableMessage(LaunchMode.native, _macos), isNull);
    expect(launchModeUnavailableMessage(LaunchMode.steam, _windows), isNull);
  });

  test('a game with no saved mode runs in the platform default', () {
    final unset = Game(id: 'g1', title: 'Subahibi');
    expect(effectiveLaunchMode(unset, _linux), LaunchMode.proton);
    expect(effectiveLaunchMode(unset, _macos), LaunchMode.native);
    expect(effectiveLaunchMode(unset, _windows), LaunchMode.native);
  });

  test('a saved mode wins over the platform default', () {
    final saved = Game(
      id: 'g1',
      title: 'Subahibi',
      launch: LaunchOverrides(mode: LaunchMode.proton),
    );
    expect(effectiveLaunchMode(saved, _macos), LaunchMode.proton);
  });

  test('launching a saved mode the platform lacks is refused', () {
    final game = Game(
      id: 'g1',
      title: 'Subahibi',
      launch: LaunchOverrides(
        mode: LaunchMode.proton,
        executable: '/games/suba/game.exe',
      ),
    );
    expect(
      () => buildLaunchCommand(
        game,
        _defaults,
        hostEnv: const {},
        umuRunPath: '/usr/bin/umu-run',
        platform: _macos,
      ),
      throwsA(
        isA<LaunchConfigError>().having(
          (e) => e.message,
          'message',
          "Proton isn't available on macOS.",
        ),
      ),
    );
    expect(game.launch.mode, LaunchMode.proton);
  });
}
