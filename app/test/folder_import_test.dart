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
import 'package:tsumige/src/core/paths.dart';
import 'package:tsumige/src/core/vndb.dart';
import 'package:tsumige/src/features/library/domain/folder_import.dart';

VnSearchResult _vn(String id, String title, {List<String> titles = const []}) =>
    VnSearchResult(id: id, title: title, titles: titles);

const _linux = HostPlatform(HostOs.linux);
const _macos = HostPlatform(HostOs.macos);

void _exe(String root, String relative, {int size = 10}) {
  final file = File(p.join(root, relative));
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(List.filled(size, 0));
}

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('tsumige_folder_import_test_');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  group('scanImportFolder', () {
    test('skips hidden subfolders and lists the rest by name', () async {
      _exe(temp.path, '.Hidden/Game.exe');
      _exe(temp.path, 'beta/Beta.exe');
      _exe(temp.path, 'Alpha/Alpha.exe');
      final folders = await scanImportFolder(temp.path, _linux);
      expect([for (final f in folders) f.name], ['Alpha', 'beta']);
    });

    test(
      'picks the game exe over installers, crash handlers and redist',
      () async {
        _exe(temp.path, 'Alpha/Game.exe');
        _exe(temp.path, 'Alpha/unins000.exe');
        _exe(temp.path, 'Alpha/setup.exe');
        _exe(temp.path, 'Alpha/UnityCrashHandler64.exe');
        _exe(temp.path, 'Alpha/redist/vc_redist.exe');
        final folder = (await scanImportFolder(temp.path, _linux)).single;
        expect([for (final e in folder.exes) e.relative], ['Game.exe']);
        expect(chooseExe(folder, const [])!.relative, 'Game.exe');
      },
    );

    test('prefers top-level, non-patch and non-launcher exes', () async {
      _exe(temp.path, 'Beta/Launcher.exe', size: 900);
      _exe(temp.path, 'Beta/Beta.exe', size: 100);
      _exe(temp.path, 'Beta/Beta_patch.exe', size: 800);
      _exe(temp.path, 'Beta/bin/Beta.exe', size: 700);
      final folder = (await scanImportFolder(temp.path, _linux)).single;
      expect(
        [for (final e in folder.exes) e.relative],
        ['Beta.exe', p.join('bin', 'Beta.exe')],
      );
      expect(chooseExe(folder, const [])!.relative, 'Beta.exe');
    });

    test('a launcher is kept when it is the only exe', () async {
      _exe(temp.path, 'Epsilon/Launcher.exe');
      final folder = (await scanImportFolder(temp.path, _linux)).single;
      expect([for (final e in folder.exes) e.relative], ['Launcher.exe']);
    });

    test('a game at level 3 is found by its own folder name', () async {
      _exe(temp.path, 'Gamma/a/b/Deep.exe');
      final folder = (await scanImportFolder(temp.path, _linux)).single;
      expect(folder.name, 'b');
      expect(folder.path, p.join(temp.path, 'Gamma', 'a', 'b'));
      expect([for (final e in folder.exes) e.relative], ['Deep.exe']);
    });

    test('a game at level 4 is not searched', () async {
      _exe(temp.path, 'Gamma/a/b/c/TooDeep.exe');
      expect(await scanImportFolder(temp.path, _linux), isEmpty);
    });

    test('candidate lists are relative to the subfolder', () async {
      _exe(temp.path, 'Delta/Delta.exe');
      _exe(temp.path, 'Delta/bin/Other.exe');
      final folder = (await scanImportFolder(temp.path, _linux)).single;
      expect(
        [for (final e in folder.exes) e.relative],
        ['Delta.exe', p.join('bin', 'Other.exe')],
      );
      expect(folder.exes.every((e) => p.isAbsolute(e.path)), isTrue);
    });

    test('a folder with no launchable is not listed', () async {
      _exe(temp.path, 'Empty/readme.txt');
      expect(await scanImportFolder(temp.path, _linux), isEmpty);
    });

    test('the choice prefers the title match over the size', () async {
      _exe(temp.path, 'Zeta/Other.exe', size: 500);
      _exe(temp.path, 'Zeta/Zeta Quest.exe', size: 10);
      final folder = (await scanImportFolder(temp.path, _linux)).single;
      expect(chooseExe(folder, const [])!.relative, 'Zeta Quest.exe');
    });

    test('a top-level exe wins over a better title match', () async {
      _exe(temp.path, 'Zeta/bin/Zeta Quest.exe', size: 10);
      _exe(temp.path, 'Zeta/Other.exe', size: 5);
      final folder = (await scanImportFolder(temp.path, _linux)).single;
      expect(chooseExe(folder, const ['Zeta Quest'])!.relative, 'Other.exe');
    });
  });

  group('game detection', () {
    test('a folder with movie, savedata and system is one game', () async {
      _exe(temp.path, 'Amanatsu/Amanatsu.exe');
      _exe(temp.path, 'Amanatsu/movie/op.mp4.exe');
      _exe(temp.path, 'Amanatsu/savedata/save.exe');
      _exe(temp.path, 'Amanatsu/system/system.exe');
      final folders = await scanImportFolder(
        p.join(temp.path, 'Amanatsu'),
        _linux,
      );
      expect([for (final f in folders) f.name], ['Amanatsu']);
      expect(folders.single.path, p.join(temp.path, 'Amanatsu'));
    });

    test(
      'a library root gives its games and no empty or junk folders',
      () async {
        _exe(temp.path, 'Alpha/Alpha.exe');
        _exe(temp.path, 'Beta/Beta.exe');
        _exe(temp.path, 'Gamma/Gamma.exe');
        Directory(p.join(temp.path, 'Empty')).createSync();
        _exe(temp.path, 'JunkOnly/unins000.exe');
        _exe(temp.path, 'JunkOnly/setup.exe');
        final folders = await scanImportFolder(temp.path, _linux);
        expect([for (final f in folders) f.name], ['Alpha', 'Beta', 'Gamma']);
      },
    );

    test('a generic bin folder names its game by the folder above', () async {
      _exe(temp.path, 'Game/bin/Game.exe');
      final folders = await scanImportFolder(temp.path, _linux);
      expect([for (final f in folders) f.name], ['Game']);
    });

    test('picking the game folder itself with a bin exe gives that folder', () async {
      _exe(temp.path, 'Game/bin/Game.exe');
      final folders = await scanImportFolder(p.join(temp.path, 'Game'), _linux);
      expect(folders.single.name, 'Game');
      expect(folders.single.path, p.join(temp.path, 'Game'));
    });

    test('two exe dirs under one game folder are one game', () async {
      _exe(temp.path, 'Game/bin/Game.exe', size: 10);
      _exe(temp.path, 'Game/x64/Game64.exe', size: 20);
      final folders = await scanImportFolder(temp.path, _linux);
      expect([for (final f in folders) f.name], ['Game']);
      expect(
        [for (final e in folders.single.exes) e.relative]..sort(),
        [p.join('bin', 'Game.exe'), p.join('x64', 'Game64.exe')],
      );
    });

    test('a lone game folder holding one exe is named by that folder', () async {
      _exe(temp.path, 'OnlyGame/OnlyGame.exe');
      final folders = await scanImportFolder(temp.path, _linux);
      expect([for (final f in folders) f.name], ['OnlyGame']);
    });

    test('a studio folder is not a game when its child is', () async {
      _exe(temp.path, 'Studio/Game/Game.exe');
      final folders = await scanImportFolder(temp.path, _linux);
      expect([for (final f in folders) f.name], ['Game']);
    });

    test('a bin subfolder with a junk tools exe is still one game', () async {
      _exe(temp.path, 'Game/bin/game.exe');
      _exe(temp.path, 'Game/tools/config.exe');
      final folders = await scanImportFolder(temp.path, _linux);
      expect([for (final f in folders) f.name], ['Game']);
      expect([for (final e in folders.single.exes) e.relative], [
        p.join('bin', 'game.exe'),
      ]);
    });

    test('a game folder with movie, savedata and system is one game', () async {
      _exe(temp.path, 'Game/Game.exe');
      _exe(temp.path, 'Game/movie/intro.exe');
      _exe(temp.path, 'Game/savedata/save.exe');
      _exe(temp.path, 'Game/system/system.exe');
      final folders = await scanImportFolder(temp.path, _linux);
      expect([for (final f in folders) f.name], ['Game']);
    });

    test('games in two child folders of a studio are two games', () async {
      _exe(temp.path, 'Studio/GameA/a.exe');
      _exe(temp.path, 'Studio/GameB/b.exe');
      final folders = await scanImportFolder(temp.path, _linux);
      expect([for (final f in folders) f.name], ['GameA', 'GameB']);
    });

    test('a game deeper than depth 3 is not found', () async {
      _exe(temp.path, 'A/B/C/Game/Game.exe');
      expect(await scanImportFolder(temp.path, _linux), isEmpty);
    });

    test('a .app bundle is a game on macOS only', () async {
      Directory(p.join(temp.path, 'Mac', 'Mac.app', 'Contents'))
          .createSync(recursive: true);
      final mac = await scanImportFolder(temp.path, _macos);
      expect([for (final f in mac) f.exes.single.relative], ['Mac.app']);
      expect(await scanImportFolder(temp.path, _linux), isEmpty);
    });

    test('an ELF binary is a game on Linux by its magic bytes', () async {
      final file = File(p.join(temp.path, 'Elf', 'game.x86_64'));
      file.parent.createSync();
      file.writeAsBytesSync([0x7f, 0x45, 0x4c, 0x46, 0, 0]);
      final folders = await scanImportFolder(temp.path, _linux);
      expect([for (final f in folders) f.name], ['Elf']);
    });

    test('a launchable picked folder is the only game', () async {
      _exe(temp.path, 'Solo/Solo.exe');
      _exe(temp.path, 'Solo/Extra/Extra.exe');
      final folders = await scanImportFolder(p.join(temp.path, 'Solo'), _linux);
      expect([for (final f in folders) f.name], ['Solo']);
    });
  });

  group('cleanFolderName', () {
    test('strips bracketed tags, versions and punctuation', () {
      expect(cleanFolderName('Game [1.02]'), 'Game');
      expect(cleanFolderName('Game_v1.02'), 'Game');
      expect(cleanFolderName('Game 2.0 Final'), 'Game Final');
      expect(cleanFolderName('a(t)rium'), 'atrium');
      expect(cleanFolderName('Rena-sensei to Pool'), 'Rena sensei to Pool');
      expect(cleanFolderName('CafeStella'), 'CafeStella');
    });
  });

  group('sequenceRatio', () {
    // Expected values from Python's difflib.SequenceMatcher(None, a, b).ratio().
    const pairs = <(String, String, double)>[
      ('abcd', 'bcde', 0.75),
      ('kitten', 'sitting', 0.6153846153846154),
      ('rena sensei', 'rena sensei to pool ryokou', 0.5945945945945946),
      ('atrium', 'a tri um', 0.8571428571428571),
      ('crack trick', 'crack trick ryokou', 0.7586206896551724),
      ('my game v1', 'my game v2 final', 0.6923076923076923),
      ('ab', 'xyz', 0.0),
    ];
    for (final (a, b, expected) in pairs) {
      test('$a vs $b matches Python', () {
        expect(sequenceRatio(a, b), closeTo(expected, 1e-12));
      });
    }

    test('two empty strings are identical', () {
      expect(sequenceRatio('', ''), 1.0);
    });
  });

  group('normalise and similarity', () {
    test('case, punctuation and spacing are ignored', () {
      expect(normalise('  CRACK≡TRICK!  '), 'crack trick');
      expect(normalise('a(t)rium'), 'a t rium');
      expect(similarity('DEMO', 'demo'), 1.0);
    });

    test('a substring match scores at least 0.85', () {
      expect(
        similarity('Rena sensei', 'Rena-sensei to Pool Ryokou'),
        closeTo(0.85 + 0.14 * 11 / 26, 1e-12),
      );
    });
  });

  group('matchFolder', () {
    test('an exact unique title is a match', () {
      final m = matchFolder('DEMO', [_vn('v1', 'DEMO'), _vn('v2', 'Other')]);
      expect(m.state, ImportMatchState.matched);
      expect(m.vn!.id, 'v1');
    });

    test('a tie at 1.0 is a check', () {
      final m = matchFolder('DEMO', [_vn('v1', 'DEMO'), _vn('v2', 'DEMO')]);
      expect(m.state, ImportMatchState.check);
      expect(m.vn!.id, 'v1');
    });

    test('a clear lead at 0.78 or better is a match', () {
      final m = matchFolder('Rena sensei', [
        _vn('v1', 'Rena-sensei to Pool Ryokou'),
      ]);
      expect(m.state, ImportMatchState.matched);
      expect(m.vn!.id, 'v1');
    });

    test('a close second place makes a check even above 0.78', () {
      final m = matchFolder('Solo Quest', [
        _vn('v1', 'Solo Quest Remake'),
        _vn('v2', 'Solo Quest Remaster'),
      ]);
      expect(m.state, ImportMatchState.check);
      expect(m.vn!.id, 'v1');
    });

    test('a score from 0.65 to 0.78 is a check', () {
      final m = matchFolder('my game v1', [_vn('v1', 'my game v2 final')]);
      expect(m.state, ImportMatchState.check);
      expect(m.vn!.id, 'v1');
    });

    test('a score below 0.65 is no match with no entry', () {
      final m = matchFolder('abcd', [_vn('v1', 'xyz')]);
      expect(m.state, ImportMatchState.none);
      expect(m.vn, isNull);
    });

    test('no results is no match', () {
      final m = matchFolder('DEMO', const []);
      expect(m.state, ImportMatchState.none);
      expect(m.vn, isNull);
    });

    test('alternative and romanised titles count', () {
      final m = matchFolder('Atrium', [
        _vn('v1', 'a(t)rium', titles: ['Atrium']),
        _vn('v2', 'Other'),
      ]);
      expect(m.state, ImportMatchState.matched);
      expect(m.vn!.id, 'v1');
    });
  });

  group('word boundaries', () {
    test('a folder that starts mid-word in a longer title is not matched', () {
      final results = [
        VnSearchResult(
          id: 'v1',
          title: 'GameBook DS Aquarian Age Perpetual Period',
        ),
      ];
      final match = matchFolder('GameB', results);
      expect(match.state, isNot(ImportMatchState.matched));
      expect(match.state, ImportMatchState.none);
    });

    test('a folder that is the words at the start of a title still matches', () {
      final results = [
        VnSearchResult(
          id: 'v1',
          title: "Café Stella and the Reaper's Butterflies",
        ),
      ];
      final match = matchFolder('CafeStella', results);
      expect(match.state, ImportMatchState.matched);
      expect(match.vn!.id, 'v1');
    });
  });

  group('aliases', () {
    test('an alias equal to the folder name is a match', () {
      final results = [
        VnSearchResult(
          id: 'v1',
          title: 'Completely Different Title',
          aliases: const ['Alias Folder'],
        ),
      ];
      final match = matchFolder('Alias Folder', results);
      expect(match.state, ImportMatchState.matched);
      expect(match.vn!.id, 'v1');
    });
  });

  group('reported matches', () {
    test('DEMO beats Jewel Ademox, which only contains it', () {
      final m = matchFolder('DEMO', [
        _vn('v1', 'Jewel☆Ademox'),
        _vn('v2', 'Demo Story -First Light-'),
      ]);
      expect(m.state, ImportMatchState.matched);
      expect(m.vn!.id, 'v2');
    });

    test('MoonCafe matches Moon Café and the Night Butterflies', () {
      final m = matchFolder('MoonCafe', [
        _vn('v3', "Moon Café and the Night Butterflies"),
      ]);
      expect(m.state, ImportMatchState.matched);
      expect(m.vn!.id, 'v3');
    });

    test('atrium is an exact match for a(t)rium, not Beat of the Atrium', () {
      final m = matchFolder('atrium', [
        _vn('v4', 'Beat of the Atrium'),
        _vn('v5', 'a(t)rium'),
      ]);
      expect(m.state, ImportMatchState.matched);
      expect(m.vn!.id, 'v5');
      expect(similarity('atrium', 'a(t)rium'), 1.0);
    });

    test('accents fold to plain letters', () {
      expect(normalise('Café Ñandú'), 'cafe nandu');
      expect(similarity('Cafe', 'Café'), 1.0);
    });

    test('a containment must be whole words', () {
      expect(similarity('DEMO', 'Jewel Ademox'), lessThan(0.65));
      expect(similarity('DEMO', 'DEMO Plus'), greaterThanOrEqualTo(0.85));
    });

    test('a title that is a prefix of the folder name gets no bonus', () {
      expect(similarity('Demoxa', 'DEMO'), closeTo(0.8, 1e-12));
      expect(similarity('Demoxa', 'DEMO'), lessThan(0.85));
    });

    test('an equal score keeps VNDB order', () {
      final m = matchFolder('Foo Bar', [
        _vn('v1', 'Foo Bar Deluxe'),
        _vn('v2', 'Foo Bar Deluxe'),
      ]);
      expect(m.state, ImportMatchState.check);
      expect(m.vn!.id, 'v1');
    });
  });

  group('already in library', () {
    Game game(String title, String exe, {String? vndbId}) => Game(
      id: title,
      title: title,
      vndbId: vndbId,
      launch: LaunchOverrides(executable: exe),
    );

    test('a library exe seen through a symlink is in the library', () {
      final real = Directory(p.join(temp.path, 'real'))..createSync();
      _exe(real.path, p.join('Game', 'game.exe'));
      Link(p.join(temp.path, 'link')).createSync(real.path);
      final games = [game('Sym', p.join(real.path, 'Game', 'game.exe'))];
      final exes = libraryRealExePaths(games);
      expect(
        importRowInLibrary(
          realFolder: realPath(p.join(temp.path, 'link', 'Game')),
          libraryExes: exes,
        ),
        isTrue,
      );
    });

    test('a different exe in the same folder counts as in library', () {
      final folder = Directory(p.join(temp.path, 'Kana Okaeri'))
        ..createSync();
      _exe(folder.path, p.join('Game', 'KANAOKA.EXE'));
      _exe(folder.path, 'Kana_Okaeri_setup.exe');
      final games = [
        game('Kana Okaeri', p.join(folder.path, 'Game', 'KANAOKA.EXE')),
      ];
      expect(
        importRowInLibrary(
          realFolder: realPath(folder.path),
          libraryExes: libraryRealExePaths(games),
        ),
        isTrue,
      );
    });

    test('an unrelated folder is not in the library', () {
      final folder = Directory(p.join(temp.path, 'Other'))..createSync();
      _exe(folder.path, 'Other.exe');
      final games = [game('Owned', p.join(temp.path, 'Game', 'game.exe'))];
      expect(
        importRowInLibrary(
          realFolder: realPath(folder.path),
          libraryExes: libraryRealExePaths(games),
        ),
        isFalse,
      );
    });

    test('a vndb id match alone is not in the library', () {
      final games = [game('Owned', '', vndbId: 'v99')];
      expect(
        importRowInLibrary(
          realFolder: realPath(p.join(temp.path, 'Missing')),
          libraryExes: libraryRealExePaths(games),
        ),
        isFalse,
      );
    });

    test('duplicateLibraryGame matches the same file through a symlink', () {
      final real = Directory(p.join(temp.path, 'real'))..createSync();
      _exe(real.path, p.join('DEMO', 'DEMO.exe'));
      final link = Link(p.join(temp.path, 'link'));
      link.createSync(real.path);
      final games = [
        game('Alpha', p.join(real.path, 'DEMO', 'DEMO.exe')),
      ];
      final hit = duplicateLibraryGame(
        exe: p.join(link.path, 'DEMO', 'DEMO.exe'),
        folder: p.join(link.path, 'DEMO'),
        games: games,
      );
      expect(hit?.title, 'Alpha');
    });

    test('duplicateLibraryGame matches another exe in the folder', () {
      final folder = Directory(p.join(temp.path, 'Kana Okaeri'))
        ..createSync();
      _exe(folder.path, p.join('Game', 'KANAOKA.EXE'));
      final games = [
        game('Kana Okaeri', p.join(folder.path, 'Game', 'KANAOKA.EXE')),
      ];
      final hit = duplicateLibraryGame(
        exe: p.join(folder.path, 'Kana_Okaeri_setup.exe'),
        folder: folder.path,
        games: games,
      );
      expect(hit?.title, 'Kana Okaeri');
    });

    test('duplicateLibraryGame returns null for a new exe', () {
      final folder = Directory(p.join(temp.path, 'New'))..createSync();
      _exe(folder.path, 'New.exe');
      final games = [game('Owned', p.join(temp.path, 'Old', 'old.exe'))];
      expect(
        duplicateLibraryGame(
          exe: p.join(folder.path, 'New.exe'),
          folder: folder.path,
          games: games,
        ),
        isNull,
      );
    });
  });

  group('query variants', () {
    test('a CamelCase name splits at lower-to-Upper boundaries', () {
      expect(splitCamelQuery('MakingLovers'), 'Making Lovers');
      expect(splitCamelQuery('PhantomENG'), 'Phantom ENG');
    });

    test('an all-caps name stays whole', () {
      expect(splitCamelQuery('KANADE'), isNull);
      expect(splitCamelQuery('Making Lovers'), isNull);
    });

    test('a trailing language tag is dropped', () {
      expect(stripLanguageTag('PhantomENG'), 'Phantom');
      expect(stripLanguageTag('Game ENG'), 'Game');
      expect(stripLanguageTag('Game Japanese'), 'Game');
      expect(stripLanguageTag('GameJp'), 'Game');
      expect(stripLanguageTag('GameEnglish'), 'Game');
    });

    test('a lowercase word ending is not a tag', () {
      expect(stripLanguageTag('Raven'), isNull);
      expect(stripLanguageTag('Heaven'), isNull);
      expect(stripLanguageTag('Eden'), isNull);
      expect(stripLanguageTag('Kitchen'), isNull);
      expect(stripLanguageTag('Heaven Eng'), 'Heaven');
    });

    test('names without a tag stay whole', () {
      expect(stripLanguageTag('KANADE'), isNull);
      expect(stripLanguageTag('OPEN'), isNull);
      expect(stripLanguageTag('Making Lovers'), isNull);
    });

    test('variants run cleaned, split, then untagged', () {
      expect(folderQueryVariants('MakingLovers'), [
        'MakingLovers',
        'Making Lovers',
      ]);
      expect(folderQueryVariants('PhantomENG'), [
        'PhantomENG',
        'Phantom ENG',
        'Phantom',
      ]);
      expect(folderQueryVariants('KANADE'), ['KANADE']);
    });

    test('parent folders run nearest first', () {
      final exeDir = p.join(
        'Lib',
        'Phantom of Inferno Nitro Archive',
        'PhantomENG',
      );
      expect(
        parentFolderQueries(exeDir: exeDir, root: 'Lib'),
        ['Phantom of Inferno Nitro Archive'],
      );
      expect(parentFolderQueries(exeDir: exeDir, root: null), isEmpty);
    });
  });

  group('lookupFolderMatch', () {
    test('a split name finds what the glued name misses', () async {
      final asked = <String>[];
      final match = await lookupFolderMatch(
        query: 'MakingLovers',
        parentQueries: const [],
        search: (query) async {
          asked.add(query);
          return query == 'Making Lovers' ? [_vn('v21552', 'Making Lovers')] : const [];
        },
      );
      expect(asked, ['MakingLovers', 'Making Lovers']);
      expect(match.state, ImportMatchState.matched);
      expect(match.vn!.id, 'v21552');
    });

    test('a parent folder finds what the exe folder misses', () async {
      final asked = <String>[];
      final match = await lookupFolderMatch(
        query: 'PhantomENG',
        parentQueries: ['Phantom of Inferno Nitro Archive'],
        search: (query) async {
          asked.add(query);
          if (query == 'Phantom of Inferno Nitro Archive') {
            return [_vn('v45', 'Phantom of Inferno')];
          }
          return const <VnSearchResult>[];
        },
      );
      expect(asked.last, 'Phantom of Inferno Nitro Archive');
      expect(match.state, ImportMatchState.matched);
      expect(match.vn!.id, 'v45');
    });

    test('stops at the first matched', () async {
      final asked = <String>[];
      final match = await lookupFolderMatch(
        query: 'DEMO',
        parentQueries: ['Parent'],
        search: (query) async {
          asked.add(query);
          return [_vn('v1', 'DEMO')];
        },
      );
      expect(asked, ['DEMO']);
      expect(match.state, ImportMatchState.matched);
    });

    test('otherwise keeps the first check', () async {
      final match = await lookupFolderMatch(
        query: 'Solo Quest',
        parentQueries: const [],
        search: (query) async => [
          _vn('v7', 'Solo Quest Remake'),
          _vn('v8', 'Solo Quest Remaster'),
        ],
      );
      expect(match.state, ImportMatchState.check);
      expect(match.vn!.id, 'v7');
    });

    test('a failing variant keeps an earlier check', () async {
      final match = await lookupFolderMatch(
        query: 'Solo Quest',
        parentQueries: const ['Parent A', 'Parent B'],
        search: (query) async {
          if (query == 'Parent B') {
            throw const VndbException('HTTP 500', statusCode: 500);
          }
          if (query == 'Parent A') return const [];
          return [
            _vn('v7', 'Solo Quest Remake'),
            _vn('v8', 'Solo Quest Remaster'),
          ];
        },
      );
      expect(match.state, ImportMatchState.check);
      expect(match.vn!.id, 'v7');
    });

    test('a failure with no check is rethrown', () async {
      await expectLater(
        lookupFolderMatch(
          query: 'Solo Quest',
          parentQueries: const ['Parent A'],
          search: (query) async {
            if (query == 'Parent A') return const [];
            throw const VndbException('HTTP 500', statusCode: 500);
          },
        ),
        throwsA(isA<VndbException>()),
      );
    });

    test('each variant keeps its shortened retry', () async {
      final asked = <String>[];
      final match = await lookupFolderMatch(
        query: 'Game Title - Subtitle Here',
        parentQueries: const [],
        search: (query) async {
          asked.add(query);
          return query == 'Game Title' ? [_vn('v1', 'Game Title')] : const [];
        },
      );
      expect(asked, ['Game Title - Subtitle Here', 'Game Title']);
      expect(match.state, ImportMatchState.matched);
    });
  });

  group('shortenedQuery and lookupFolder', () {
    test('drops a subtitle after " - " or a colon', () {
      expect(shortenedQuery('Game Title - Subtitle Here'), 'Game Title');
      expect(shortenedQuery('Game: Sub'), 'Game');
    });

    test('drops the last two words of a long name', () {
      expect(shortenedQuery('One Two Three Four'), 'One Two');
    });

    test('a short name with nothing to drop has no retry', () {
      expect(shortenedQuery('DEMO'), isNull);
    });

    test(
      'retries the shortened query only when the first search is empty',
      () async {
        final asked = <String>[];
        final results = await lookupFolder('Game Title - Subtitle Here', (
          query,
        ) async {
          asked.add(query);
          return query == 'Game Title' ? [_vn('v1', 'Game Title')] : const [];
        });
        expect(asked, ['Game Title - Subtitle Here', 'Game Title']);
        expect(results.single.id, 'v1');

        asked.clear();
        await lookupFolder('Game Title - Subtitle Here', (query) async {
          asked.add(query);
          return [_vn('v2', 'Other')];
        });
        expect(asked, ['Game Title - Subtitle Here']);
      },
    );
  });

  group('VndbRequestQueue', () {
    late DateTime now;
    late List<Duration> waits;

    setUp(() {
      now = DateTime.utc(2026, 1, 1);
      waits = [];
    });

    VndbRequestQueue queueWith(
      Future<List<VnSearchResult>> Function(String) search,
    ) => VndbRequestQueue(
      search: search,
      now: () => now,
      delay: (wait) async {
        waits.add(wait);
        now = now.add(wait);
      },
    );

    test('requests start at least 1.6 s apart', () async {
      final started = <DateTime>[];
      final queue = queueWith((query) async {
        started.add(now);
        return const [];
      });
      await Future.wait([
        queue.run('a'),
        queue.run('b'),
        queue.run('c'),
      ]);
      expect(started, hasLength(3));
      expect(
        started[1].difference(started[0]),
        greaterThanOrEqualTo(const Duration(milliseconds: 1600)),
      );
      expect(
        started[2].difference(started[1]),
        greaterThanOrEqualTo(const Duration(milliseconds: 1600)),
      );
    });

    test('a 429 waits 60 s and retries the same request', () async {
      var calls = 0;
      final queue = queueWith((query) async {
        calls++;
        if (calls <= 2) {
          throw const VndbException('HTTP 429', statusCode: 429);
        }
        return [_vn('v1', 'DEMO')];
      });
      final results = await queue.run('DEMO');
      expect(results.single.id, 'v1');
      expect(calls, 3);
      expect(waits, const [
        Duration(seconds: 60),
        Duration(seconds: 60),
      ]);
    });

    test('after 3 retries the error is rethrown', () async {
      var calls = 0;
      final queue = queueWith((query) async {
        calls++;
        throw const VndbException('HTTP 429', statusCode: 429);
      });
      await expectLater(queue.run('DEMO'), throwsA(isA<VndbException>()));
      expect(calls, 4);
      expect(waits, hasLength(3));
    });

    test('cancel stops a retry before its wait and any later request', () async {
      late final VndbRequestQueue queue;
      var calls = 0;
      queue = queueWith((query) async {
        calls++;
        queue.cancel();
        throw const VndbException('HTTP 429', statusCode: 429);
      });
      await expectLater(queue.run('a'), throwsA(isA<VndbCancelled>()));
      await expectLater(queue.run('b'), throwsA(isA<VndbCancelled>()));
      expect(calls, 1);
      expect(waits, isEmpty);
    });

    test('other errors are not retried', () async {
      var calls = 0;
      final queue = queueWith((query) async {
        calls++;
        throw const VndbException('HTTP 500', statusCode: 500);
      });
      await expectLater(queue.run('DEMO'), throwsA(isA<VndbException>()));
      expect(calls, 1);
      expect(waits, isEmpty);
    });
  });
}
