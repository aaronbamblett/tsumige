// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tsumige/src/core/host_platform.dart';
import 'package:tsumige/src/core/model.dart';
import 'package:tsumige/src/features/library/domain/launch_detection.dart';

const _linux = HostPlatform(HostOs.linux);
const _macos = HostPlatform(HostOs.macos);
const _windows = HostPlatform(HostOs.windows);

void _file(String path, [List<int> bytes = const [0, 0, 0, 0]]) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);
}

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('tsumige_launch_detection_');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  String at(String relative) => p.join(temp.path, relative);

  group('detectLaunchMode', () {
    test('a game in a Steam library takes its app id on every OS', () async {
      _file(
        at('steamapps/appmanifest_1234.acf'),
        '"AppState"\n{\n\t"appid"\t\t"1234"\n\t"installdir"\t\t"CafeStella"\n}'
            .codeUnits,
      );
      _file(at('steamapps/appmanifest_999.acf'),
          '"AppState"\n{\n\t"appid"\t\t"999"\n\t"installdir"\t\t"Other"\n}'
              .codeUnits);
      final exe = at('steamapps/common/CafeStella/CafeStella.exe');
      for (final platform in [_linux, _macos, _windows]) {
        final result = await detectLaunchMode(exe, platform);
        expect(result.mode, LaunchMode.steam);
        expect(result.steamAppId, 1234);
      }
    });

    test('the folder itself in a Steam library is detected too', () async {
      _file(
        at('steamapps/appmanifest_42.acf'),
        '"installdir"\t\t"Folder"\n"appid"\t\t"42"'.codeUnits,
      );
      final result = await detectLaunchMode(
        at('steamapps/common/Folder'),
        _linux,
      );
      expect((result.mode, result.steamAppId), (LaunchMode.steam, 42));
    });

    test('without a matching manifest the usual rules apply', () async {
      _file(
        at('steamapps/appmanifest_1.acf'),
        '"installdir"\t\t"Other"\n"appid"\t\t"1"'.codeUnits,
      );
      final result = await detectLaunchMode(
        at('steamapps/common/Lonely/Lonely.exe'),
        _linux,
      );
      expect((result.mode, result.steamAppId), (LaunchMode.proton, null));
    });

    test('an exe is Proton on Linux and Native on Windows', () async {
      expect(
        (await detectLaunchMode('/games/Game.exe', _linux)).mode,
        LaunchMode.proton,
      );
      expect(
        (await detectLaunchMode('/games/Game.exe', _windows)).mode,
        LaunchMode.native,
      );
    });

    test('a .app bundle is Native on macOS and the default elsewhere', () async {
      expect(
        (await detectLaunchMode('/games/Game.app', _macos)).mode,
        LaunchMode.native,
      );
      expect(
        (await detectLaunchMode('/games/Game.app', _linux)).mode,
        LaunchMode.proton,
      );
    });

    test('an ELF binary on Linux is Native, found by magic bytes', () async {
      _file(at('Game/game'), [0x7f, 0x45, 0x4c, 0x46, 2, 1]);
      expect(
        (await detectLaunchMode(at('Game/game'), _linux)).mode,
        LaunchMode.native,
      );
    });

    test('a Mach-O binary on macOS is Native, found by magic bytes', () async {
      _file(at('Game/game'), [0xcf, 0xfa, 0xed, 0xfe]);
      expect(
        (await detectLaunchMode(at('Game/game'), _macos)).mode,
        LaunchMode.native,
      );
      expect(
        (await detectLaunchMode(at('Game/game'), _linux)).mode,
        LaunchMode.proton,
      );
    });

    test('a .sh on Linux, a .AppImage on Linux and a .command on macOS are Native', () async {
      expect(
        (await detectLaunchMode('/g/run.sh', _linux)).mode,
        LaunchMode.native,
      );
      expect(
        (await detectLaunchMode('/g/Game.AppImage', _linux)).mode,
        LaunchMode.native,
      );
      expect(
        (await detectLaunchMode('/g/Game.command', _macos)).mode,
        LaunchMode.native,
      );
    });

    test('anything else gets the platform default', () async {
      _file(at('Game/readme.txt'), 'notes'.codeUnits);
      expect(
        (await detectLaunchMode(at('Game/readme.txt'), _linux)).mode,
        LaunchMode.proton,
      );
      expect(
        (await detectLaunchMode(at('Game/readme.txt'), _macos)).mode,
        LaunchMode.native,
      );
    });
  });
}
