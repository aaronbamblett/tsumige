// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tsumige/src/core/launch/detect.dart';

const _fakeHome = '/home/testuser';

late Directory _root;

Map<String, String> _env({String? fakePath}) => {
  'HOME': _fakeHome,
  'PATH': ?fakePath,
};

String _at(String absolutePath) =>
    p.join(_root.path, p.relative(absolutePath, from: '/'));

void _makeFile(String absolutePath) {
  File(_at(absolutePath)).createSync(recursive: true);
}

void _makeDir(String absolutePath) {
  Directory(_at(absolutePath)).createSync(recursive: true);
}

void _makeFileWith(String absolutePath, String content) {
  final file = File(_at(absolutePath));
  file.createSync(recursive: true);
  file.writeAsStringSync(content);
}

void main() {
  setUp(() {
    _root = Directory.systemTemp.createTempSync('tsumige_detect_test');
  });

  tearDown(() {
    try {
      _root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a Lutris runner is found with source lutris', () {
    _makeFile(
      '$_fakeHome/.local/share/lutris/runners/wine/lutris-GE-8-26/bin/wine',
    );

    final runners = detectWineRunners(_env(), fsRoot: _root.path);

    expect(runners, hasLength(1));
    expect(runners.single.name, 'lutris-GE-8-26');
    expect(runners.single.source, 'lutris');
    expect(
      runners.single.binary,
      _at('$_fakeHome/.local/share/lutris/runners/wine/lutris-GE-8-26/bin/wine'),
    );
  });

  test('a Bottles runner is found', () {
    _makeFile('$_fakeHome/.local/share/bottles/runners/soda-9.0/bin/wine');

    final runners = detectWineRunners(_env(), fsRoot: _root.path);

    expect(runners, hasLength(1));
    expect(runners.single.name, 'soda-9.0');
    expect(runners.single.source, 'bottles');
  });

  test('a Flatpak Lutris runner is found', () {
    _makeFile(
      '$_fakeHome/.var/app/net.lutris.Lutris/data/lutris/runners/wine/lutris-GE-8-26/bin/wine',
    );

    final runners = detectWineRunners(_env(), fsRoot: _root.path);

    expect(runners, hasLength(1));
    expect(runners.single.name, 'lutris-GE-8-26');
    expect(runners.single.source, 'lutris');
  });

  test('a wine on a fake PATH is found', () {
    _makeFile('/fakebin/wine');

    final runners = detectWineRunners(
      _env(fakePath: '/fakebin'),
      fsRoot: _root.path,
    );

    expect(runners, hasLength(1));
    expect(runners.single.name, 'System wine');
    expect(runners.single.binary, _at('/fakebin/wine'));
    expect(runners.single.source, 'path');
  });

  test('a Proton in compatibilitytools.d is found, without proton ignored', () {
    _makeFile(
      '$_fakeHome/.local/share/Steam/compatibilitytools.d/GE-Proton9-20/proton',
    );
    _makeDir('$_fakeHome/.local/share/Steam/compatibilitytools.d/EmptyFolder');

    final runners = detectProtonRunners(_env(), fsRoot: _root.path);

    expect(runners, hasLength(1));
    expect(runners.single.name, 'GE-Proton9-20');
    expect(
      runners.single.path,
      _at('$_fakeHome/.local/share/Steam/compatibilitytools.d/GE-Proton9-20'),
    );
  });

  test('a Proton in steamapps/common is found', () {
    _makeFile('$_fakeHome/.local/share/Steam/steamapps/common/Proton 9.0/proton');

    final runners = detectProtonRunners(_env(), fsRoot: _root.path);

    expect(runners, hasLength(1));
    expect(runners.single.name, 'Proton 9.0');
  });

  test('a prefix with a manifest is found with its game name', () {
    _makeDir('$_fakeHome/.local/share/Steam/steamapps/compatdata/1230140/pfx');
    _makeFileWith(
      '$_fakeHome/.local/share/Steam/steamapps/appmanifest_1230140.acf',
      '"AppState"\n{\n\t"appid"\t\t"1230140"\n'
      '\t"name"\t\t"Demo Story -First Light-"\n}\n',
    );

    final prefixes = detectSteamPrefixes(_env(), fsRoot: _root.path);

    expect(prefixes, hasLength(1));
    expect(prefixes.single.appId, '1230140');
    expect(prefixes.single.gameName, 'Demo Story -First Light-');
    expect(
      prefixes.single.path,
      _at('$_fakeHome/.local/share/Steam/steamapps/compatdata/1230140/pfx'),
    );
  });

  test('a prefix without a manifest has a null name', () {
    _makeDir('$_fakeHome/.local/share/Steam/steamapps/compatdata/999/pfx');

    final prefixes = detectSteamPrefixes(_env(), fsRoot: _root.path);

    expect(prefixes, hasLength(1));
    expect(prefixes.single.appId, '999');
    expect(prefixes.single.gameName, isNull);
  });

  test('a symlinked duplicate runner is listed once', () {
    const real =
        '$_fakeHome/.local/share/lutris/runners/wine/lutris-GE-8-26';
    _makeFile('$real/bin/wine');
    Link(_at('$_fakeHome/.local/share/bottles/runners/alias-runner'))
        .createSync(_at(real), recursive: true);

    final runners = detectWineRunners(_env(), fsRoot: _root.path);

    expect(runners, hasLength(1));
  });

  test('nonexistent HOME folders give empty lists, not exceptions', () {
    const env = {'HOME': '/does/not/exist', 'PATH': '/does/not/exist'};

    expect(detectWineRunners(env), isEmpty);
    expect(detectProtonRunners(env), isEmpty);
    expect(detectSteamPrefixes(env), isEmpty);
    expect(detectWineRunners(const {}), isEmpty);
    expect(detectProtonRunners(const {}), isEmpty);
    expect(detectSteamPrefixes(const {}), isEmpty);
  });

  test('runners sort by name case-insensitively', () {
    _makeFile('$_fakeHome/.local/share/bottles/runners/zulu/bin/wine');
    _makeFile(
      '$_fakeHome/.local/share/lutris/runners/wine/Alpha/bin/wine',
    );
    _makeFile('$_fakeHome/.local/share/bottles/runners/mike/bin/wine');

    final runners = detectWineRunners(_env(), fsRoot: _root.path);

    expect(runners.map((r) => r.name), ['Alpha', 'mike', 'zulu']);
  });

  test('prefixes sort by game name, then app id', () {
    _makeDir('$_fakeHome/.local/share/Steam/steamapps/compatdata/2/pfx');
    _makeDir('$_fakeHome/.local/share/Steam/steamapps/compatdata/1/pfx');
    _makeDir('$_fakeHome/.local/share/Steam/steamapps/compatdata/3/pfx');
    _makeFileWith(
      '$_fakeHome/.local/share/Steam/steamapps/appmanifest_2.acf',
      '"name"\t\t"beta"\n',
    );
    _makeFileWith(
      '$_fakeHome/.local/share/Steam/steamapps/appmanifest_1.acf',
      '"name"\t\t"alpha"\n',
    );

    final prefixes = detectSteamPrefixes(_env(), fsRoot: _root.path);

    expect(prefixes.map((e) => e.appId), ['1', '2', '3']);
  });
}
