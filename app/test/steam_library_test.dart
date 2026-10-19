// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tsumige/src/core/host_platform.dart';
import 'package:tsumige/src/core/vndb.dart';
import 'package:tsumige/src/features/library/domain/folder_import.dart';
import 'package:tsumige/src/features/library/domain/steam_library.dart';

class _Fs {
  _Fs(this.context);

  final p.Context context;
  final Map<String, String> files = {};
  final Set<String> dirs = {};
  final Map<String, String> links = {};

  void file(String path, String content) {
    files[path] = content;
    var dir = context.dirname(path);
    while (dir != context.dirname(dir)) {
      dirs.add(dir);
      dir = context.dirname(dir);
    }
    dirs.add(dir);
  }

  bool dirExists(String path) => dirs.contains(path);

  String resolve(String path) => links[path] ?? path;

  String? read(String path) => files[path];

  List<String> list(String dir) => {
    for (final path in files.keys)
      if (context.dirname(path) == dir) path,
    for (final path in dirs)
      if (path != dir && context.dirname(path) == dir) path,
  }.toList();
}

String _manifest(
  int appId,
  String name,
  String installDir, {
  String? stateFlags = '4',
}) => '''
"AppState"
{
\t"appid"\t\t"$appId"
\t"name"\t\t"$name"
\t"installdir"\t\t"$installDir"
${stateFlags == null ? '' : '\t"StateFlags"\t\t"$stateFlags"\n'}}
''';

const _macos = HostPlatform(HostOs.macos);
const _linux = HostPlatform(HostOs.linux);
const _windows = HostPlatform(HostOs.windows);

Future<List<InstalledSteamGame>> _games(
  _Fs fs,
  HostPlatform platform,
  Map<String, String> env, {
  Future<String?> Function()? readWindowsSteamPath,
}) => installedSteamGames(
  platform,
  env: env,
  dirExists: fs.dirExists,
  resolvePath: fs.resolve,
  readWindowsSteamPath: readWindowsSteamPath,
  readFile: fs.read,
  listDir: fs.list,
);

void main() {
  group('parseAppManifest', () {
    test('reads appid, name, installdir and StateFlags', () {
      final parsed = parseAppManifest(
        _manifest(698780, 'Doki Doki Literature Club', 'DDLC'),
      );
      expect(parsed?.appId, 698780);
      expect(parsed?.name, 'Doki Doki Literature Club');
      expect(parsed?.installDir, 'DDLC');
      expect(parsed?.stateFlags, 4);
    });

    test('missing StateFlags reads as 0', () {
      expect(
        parseAppManifest(_manifest(1, 'Game', 'Dir', stateFlags: null))
            ?.stateFlags,
        0,
      );
    });

    test('null when the app id or the name is missing', () {
      expect(parseAppManifest('"AppState"\n{\n}'), isNull);
      expect(
        parseAppManifest('"AppState"\n{\n"appid"\t\t"1"\n}'),
        isNull,
      );
      expect(
        parseAppManifest(
          '"AppState"\n{\n"appid"\t\t"1"\n"name"\t\t"Game"\n}',
        )?.installDir,
        isEmpty,
      );
    });
  });

  group('parseLibraryFoldersVdf', () {
    test('reads every library path and undoes backslash escapes', () {
      const vdf = '''
"libraryfolders"
{
\t"0"
\t{
\t\t"path"\t\t"/home/test/.local/share/Steam"
\t}
\t"1"
\t{
\t\t"path"\t\t"C:\\\\Games\\\\Steam"
\t}
}
''';
      expect(parseLibraryFoldersVdf(vdf), [
        '/home/test/.local/share/Steam',
        r'C:\Games\Steam',
      ]);
    });
  });

  group('installedSteamGames', () {
    test('two libraries: tools filtered, duplicates deduped', () async {
      final fs = _Fs(p.context);
      const home = '/home/test';
      const root = '/home/test/.local/share/Steam';
      const extra = '/mnt/games/Steam';
      fs.file(
        '$root/steamapps/libraryfolders.vdf',
        '''
"libraryfolders"
{
\t"0"
\t{
\t\t"path"\t\t"$root"
\t}
\t"1"
\t{
\t\t"path"\t\t"$extra"
\t}
}
''',
      );
      fs.file(
        '$root/steamapps/appmanifest_698780.acf',
        _manifest(698780, 'Doki Doki Literature Club', 'DDLC'),
      );
      fs.file(
        '$root/steamapps/appmanifest_1989270.acf',
        _manifest(1989270, 'Slay the Princess', 'Slay the Princess'),
      );
      fs.file(
        '$root/steamapps/appmanifest_228980.acf',
        _manifest(
          228980,
          'Steamworks Common Redistributables',
          'Steamworks Common Redistributables',
        ),
      );
      fs.file(
        '$root/steamapps/appmanifest_1391110.acf',
        _manifest(1391110, 'Steam Linux Runtime 3.0', 'SteamLinuxRuntime_sniper'),
      );
      fs.file(
        '$root/steamapps/appmanifest_2805730.acf',
        _manifest(2805730, 'Proton 9.0', 'Proton 9.0'),
      );
      fs.file(
        '$root/steamapps/appmanifest_1096410.acf',
        _manifest(1096410, 'Coteries of New York', 'Coteries of New York',
            stateFlags: '2'),
      );
      fs.file(
        '$extra/steamapps/appmanifest_698780.acf',
        _manifest(698780, 'Doki Doki Literature Club', 'DDLC'),
      );
      fs.file(
        '$extra/steamapps/appmanifest_11.acf',
        _manifest(11, 'Half-Life', 'Half-Life', stateFlags: null),
      );

      final games = await _games(fs, _linux, {'HOME': home});
      expect([for (final game in games) game.appId], [698780, 11, 1989270]);
      expect(games[1].name, 'Half-Life');
      expect(
        games[1].installDir,
        '$extra/steamapps/common/Half-Life',
      );
      expect(
        games.first.installDir,
        '$root/steamapps/common/DDLC',
      );
    });

    test('a missing libraryfolders.vdf still reads the root library', () async {
      final fs = _Fs(p.context);
      const root = '/home/test/.local/share/Steam';
      fs.file(
        '$root/steamapps/appmanifest_698780.acf',
        _manifest(698780, 'Doki Doki Literature Club', 'DDLC'),
      );

      final games = await _games(fs, _linux, {'HOME': '/home/test'});
      expect(games, hasLength(1));
      expect(games.single.appId, 698780);
    });
  });

  group('lookupSteamMatch', () {
    const game = InstalledSteamGame(
      appId: 698780,
      name: 'Doki Doki Literature Club',
      installDir: '/steam/DDLC',
    );
    const vn = VnSearchResult(id: 'v21905', title: 'Doki Doki Literature Club');

    Future<List<VnSearchResult>> noSearch(String query) async => const [];

    test('a Steam ID hit matches without searching', () async {
      var searched = false;
      final match = await lookupSteamMatch(
        game: game,
        fetchByAppId: (appId) async {
          expect(appId, 698780);
          return vn;
        },
        search: (query) async {
          searched = true;
          return noSearch(query);
        },
      );
      expect(match.state, ImportMatchState.matched);
      expect(match.vn?.id, 'v21905');
      expect(searched, isFalse);
    });

    test('no Steam ID hit falls back to the Steam name', () async {
      final match = await lookupSteamMatch(
        game: game,
        fetchByAppId: (_) async => null,
        search: (query) async {
          expect(query, 'Doki Doki Literature Club');
          return const [vn];
        },
      );
      expect(match.state, ImportMatchState.matched);
      expect(match.vn?.id, 'v21905');
    });

    test('a name hit without an exact title is a best match', () async {
      const game = InstalledSteamGame(
        appId: 111,
        name: 'Solo Quest',
        installDir: '/steam/Solo',
      );
      final match = await lookupSteamMatch(
        game: game,
        fetchByAppId: (_) async => null,
        search: (_) async => const [
          VnSearchResult(id: 'v7', title: 'Solo Quest Remake'),
        ],
      );
      expect(match.state, ImportMatchState.check);
      expect(match.vn?.id, 'v7');
    });

    test('a name hit with an exactly equal title still matches', () async {
      const game = InstalledSteamGame(
        appId: 1569580,
        name: 'Blue-Prince',
        installDir: '/steam/Blue',
      );
      final match = await lookupSteamMatch(
        game: game,
        fetchByAppId: (_) async => null,
        search: (_) async => const [
          VnSearchResult(id: 'v1', title: 'Blue Prince'),
        ],
      );
      expect(match.state, ImportMatchState.matched);
      expect(match.vn?.id, 'v1');
    });

    test('a failing Steam ID lookup still falls back to the name', () async {
      final match = await lookupSteamMatch(
        game: game,
        fetchByAppId: (_) => throw const VndbException('HTTP 500'),
        search: (query) async => const [vn],
      );
      expect(match.state, ImportMatchState.matched);
    });

    test('nothing anywhere is none', () async {
      final match = await lookupSteamMatch(
        game: game,
        fetchByAppId: (_) async => null,
        search: noSearch,
      );
      expect(match.state, ImportMatchState.none);
      expect(match.vn, isNull);
    });
  });

  group('steamRoots', () {
    Future<List<String>> roots(
      _Fs fs,
      HostPlatform platform,
      Map<String, String> env, {
      Future<String?> Function()? readWindowsSteamPath,
    }) => steamRoots(
      platform,
      env: env,
      dirExists: fs.dirExists,
      resolvePath: fs.resolve,
      readWindowsSteamPath: readWindowsSteamPath,
    );

    test('macOS reads the Application Support path', () async {
      final fs = _Fs(p.context);
      const steam = '/Users/test/Library/Application Support/Steam';
      fs.file('$steam/steamapps/appmanifest_1.acf', 'x');
      expect(
        await roots(fs, _macos, {'HOME': '/Users/test'}),
        [steam],
      );
      expect(await roots(fs, _macos, {'HOME': '/Users/nobody'}), isEmpty);
    });

    test('Linux dedupes a symlinked root by real path', () async {
      final fs = _Fs(p.context);
      const home = '/home/test';
      fs.dirs.add('$home/.steam/steam');
      fs.dirs.add('$home/.local/share/Steam');
      fs.links['$home/.steam/steam'] = '$home/.local/share/Steam';
      expect(
        await roots(fs, _linux, {'HOME': home}),
        ['$home/.steam/steam'],
      );
    });

    test('Linux checks the Flatpak root too', () async {
      final fs = _Fs(p.context);
      const home = '/home/test';
      const flatpak =
          '$home/.var/app/com.valvesoftware.Steam/.local/share/Steam';
      fs.dirs.add(flatpak);
      expect(await roots(fs, _linux, {'HOME': home}), [flatpak]);
    });

    test('Linux with no HOME finds nothing', () async {
      final fs = _Fs(p.context);
      expect(await roots(fs, _linux, {}), isEmpty);
    });

    test('Windows uses the registry path when set', () async {
      final fs = _Fs(p.windows);
      fs.dirs.add(r'D:\Steam');
      expect(
        await roots(
          fs,
          _windows,
          {},
          readWindowsSteamPath: () async => r'D:\Steam',
        ),
        [r'D:\Steam'],
      );
    });

    test('Windows falls back to the default path', () async {
      final fs = _Fs(p.windows);
      fs.dirs.add(r'C:\Program Files (x86)\Steam');
      expect(
        await roots(
          fs,
          _windows,
          {},
          readWindowsSteamPath: () async => null,
        ),
        [r'C:\Program Files (x86)\Steam'],
      );
    });
  });
}
