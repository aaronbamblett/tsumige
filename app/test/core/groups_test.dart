// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumige/src/core/groups.dart';
import 'package:tsumige/src/core/model.dart';
import 'package:tsumige/src/core/paths.dart';
import 'package:tsumige/src/core/store.dart';
import 'package:uuid/uuid.dart';

Game game(String id, String title, {String? released}) => Game(
      id: id,
      title: title,
      released: released,
    );

Map<String, Game> byId(List<Game> games) =>
    {for (final g in games) g.id: g};

void main() {
  test('group JSON round trip keeps last_picked_id', () {
    final group = GameGroup(
      id: 'gr1',
      name: '9-nine-',
      memberIds: ['a', 'b'],
      lastPickedId: 'b',
    );
    final json = group.toJson();
    expect(json['last_picked_id'], 'b');
    final back = GameGroup.fromJson(json);
    expect(back.id, 'gr1');
    expect(back.name, '9-nine-');
    expect(back.memberIds, ['a', 'b']);
    expect(back.lastPickedId, 'b');
  });

  test('group JSON omits last_picked_id when null', () {
    final json = GameGroup(id: 'gr1', name: 'G', memberIds: ['a', 'b']).toJson();
    expect(json.containsKey('last_picked_id'), isFalse);
    expect(GameGroup.fromJson(json).lastPickedId, isNull);
  });

  test('library file round trip keeps groups', () async {
    final dir = DataDir(
        (await Directory.systemTemp.createTemp('tsumige-groups-')).path);
    addTearDown(() => Directory(dir.root).deleteSync(recursive: true));
    resetBackupSessionForTest();
    final games = [game(const Uuid().v4(), 'Ep 1'), game(const Uuid().v4(), 'Ep 2')];
    final library = Library(games: games);
    library.groups.add(GameGroup(
        id: 'gr1',
        name: 'Series',
        memberIds: [games[0].id, games[1].id],
        lastPickedId: games[1].id));
    final loaded = LoadedLibrary(library: library);
    await saveLibrary(dir, loaded);
    final saved = jsonDecode(await dir.libraryJson.readAsString())
        as Map<String, Object?>;
    expect((saved['groups'] as List), hasLength(1));
    final again = await loadLibrary(dir);
    expect(again.library.groups, hasLength(1));
    expect(again.library.groups.single.lastPickedId, games[1].id);
  });

  test('library without groups loads with none, and saves without the key',
      () async {
    final dir = DataDir(
        (await Directory.systemTemp.createTemp('tsumige-groups-')).path);
    addTearDown(() => Directory(dir.root).deleteSync(recursive: true));
    resetBackupSessionForTest();
    final id = const Uuid().v4();
    await dir.libraryJson.writeAsString(jsonEncode({
      'schema_version': 1,
      'games': [
        {'id': id, 'title': 'Solo'}
      ],
    }));
    final loaded = await loadLibrary(dir);
    expect(loaded.library.groups, isEmpty);
    await saveLibrary(dir, loaded);
    final saved = jsonDecode(await dir.libraryJson.readAsString())
        as Map<String, Object?>;
    expect(saved.containsKey('groups'), isFalse);
  });

  test('a game is in at most one group', () {
    final games = [game('a', 'A'), game('b', 'B'), game('c', 'C')];
    final library = Library(games: games, groups: [
      GameGroup(id: 'g1', name: 'One', memberIds: ['a', 'b']),
      GameGroup(id: 'g2', name: 'Two', memberIds: ['b', 'c']),
    ]);
    normalizeGroups(library);
    expect(library.groups, hasLength(1));
    expect(library.groups.single.id, 'g1');
  });

  test('a removed member drops out, and one member dissolves the group', () {
    final games = [game('a', 'A'), game('b', 'B')];
    final library = Library(games: games, groups: [
      GameGroup(id: 'g1', name: 'One', memberIds: ['a', 'b', 'gone']),
    ]);
    normalizeGroups(library);
    expect(library.groups.single.memberIds, ['a', 'b']);
    library.games.removeWhere((g) => g.id == 'b');
    normalizeGroups(library);
    expect(library.groups, isEmpty);
  });

  test('a stale lastPickedId is cleared', () {
    final games = [game('a', 'A'), game('b', 'B')];
    final library = Library(games: games, groups: [
      GameGroup(
          id: 'g1', name: 'One', memberIds: ['a', 'b'], lastPickedId: 'gone'),
    ]);
    normalizeGroups(library);
    expect(library.groups.single.lastPickedId, isNull);
  });

  test('episode titles sort before an unnumbered one', () {
    final members = [
      game('c', '9-nine- NewEpisode'),
      game('b', '9-nine- Episode 2'),
      game('a', '9-nine- Episode 1'),
    ];
    expect(sortEpisodeIds(members), ['a', 'b', 'c']);
  });

  test('Vol.5.5 sorts between Vol.5 and Vol.6', () {
    final members = [
      game('c', 'X Vol.6'),
      game('b', 'X Vol.5.5'),
      game('a', 'X Vol.5'),
    ];
    expect(sortEpisodeIds(members), ['a', 'b', 'c']);
  });

  test('part prefixes: ep, ch, chapter, volume, part, dai-N-wa', () {
    expect(episodePartNumber('Game Ep. 3'), 3);
    expect(episodePartNumber('Game Ch. 2'), 2);
    expect(episodePartNumber('Game Chapter 10'), 10);
    expect(episodePartNumber('Game Volume 4'), 4);
    expect(episodePartNumber('Game Part 7'), 7);
    expect(episodePartNumber('ゲーム 第2話'), 2);
    expect(episodePartNumber('ゲーム 第3章'), 3);
    expect(episodePartNumber('No number here'), isNull);
  });

  test('opening picks lastPickedId, else first unplayed, else first', () {
    PlaySession session() => PlaySession(
        startedAt: DateTime.utc(2026, 1, 1), durationSeconds: 10);
    final p1 = game('a', 'Ep 1')..playSessions.add(session());
    final p2 = game('b', 'Ep 2');
    final p3 = game('c', 'Ep 3');
    final members = [p1, p2, p3];
    final group = GameGroup(id: 'g', name: 'S', memberIds: ['a', 'b', 'c']);
    expect(resolvePickedMember(group, byId(members))!.id, 'b');
    group.lastPickedId = 'c';
    expect(resolvePickedMember(group, byId(members))!.id, 'c');
    p2.playSessions.add(session());
    p3.playSessions.add(session());
    group.lastPickedId = null;
    expect(resolvePickedMember(group, byId(members))!.id, 'a');
  });

  test('short name never cuts mid-token', () {
    final eps = [game('a', 'Episode 1'), game('b', 'Episode 10')];
    final eg = GameGroup(id: 'g', name: 'Episode', memberIds: ['a', 'b']);
    final eids = byId(eps);
    expect(memberShortName(eg, eps[0], eids), '1');
    expect(memberShortName(eg, eps[1], eids), '10');
  });

  test('short name keeps the full part name after the group name', () {
    final members = [
      game('a', 'Saga Chapter 10'),
      game('b', 'Saga Chapter 11'),
      game('c', 'Saga Chapter 12'),
    ];
    final group = GameGroup(id: 'g', name: 'Saga', memberIds: ['a', 'b', 'c']);
    final ids = byId(members);
    expect(memberShortName(group, members[0], ids), 'Chapter 10');
    expect(memberShortName(group, members[1], ids), 'Chapter 11');
    expect(memberShortName(group, members[2], ids), 'Chapter 12');
  });

  test('short name strips separators after the group name', () {
    final members = [
      game('a', 'Higurashi When They Cry Hou - Ch.1 Onikakushi'),
      game('b', 'HIGURASHI WHEN THEY CRY HOU: Ch.2 Watanagashi'),
      game('c', 'Higurashi  When They Cry Hou – Ch.3 Tatarigoroshi'),
    ];
    final group = GameGroup(
        id: 'g',
        name: 'Higurashi When They Cry Hou',
        memberIds: ['a', 'b', 'c']);
    final ids = byId(members);
    expect(memberShortName(group, members[0], ids), 'Ch.1 Onikakushi');
    expect(memberShortName(group, members[1], ids), 'Ch.2 Watanagashi');
    expect(memberShortName(group, members[2], ids), 'Ch.3 Tatarigoroshi');
  });

  test('short name keeps Episode N for a 9-nine- group', () {
    final members = [
      game('a', '9-nine- Episode 1'),
      game('b', '9-nine- Episode 2'),
      game('c', '9-nine- Episode 3'),
      game('d', '9-nine- Episode 4'),
      game('e', '9-nine- NewEpisode'),
    ];
    final group = GameGroup(
        id: 'g', name: '9-nine-', memberIds: ['a', 'b', 'c', 'd', 'e']);
    final ids = byId(members);
    expect(memberShortName(group, members[0], ids), 'Episode 1');
    expect(memberShortName(group, members[3], ids), 'Episode 4');
    expect(memberShortName(group, members[4], ids), 'NewEpisode');
  });

  test('part markers inside words do not match', () {
    expect(episodePartNumber('Sleep 3'), isNull);
    expect(episodePartNumber('Deep 4'), isNull);
    expect(episodePartNumber('Episode 3'), 3);
    expect(episodePartNumber('Game Ep. 3'), 3);
  });

  test('fullwidth digits in dai-N-wa and dai-N-kan parse as ASCII', () {
    expect(episodePartNumber('ゲーム 第３話'), 3);
    expect(episodePartNumber('ゲーム 第２章'), 2);
    expect(episodePartNumber('ゲーム 第12話'), 12);
  });

  test('members without a release date sort after dated ones', () {
    final members = [
      game('a', 'X Part 1'),
      game('b', 'X Part 1', released: '2020-01-01'),
      game('c', 'X Part 1', released: '2019-01-01'),
    ];
    expect(sortEpisodeIds(members), ['c', 'b', 'a']);
  });

  test('dismissed suggestions round trip through the library file', () async {
    final dir = DataDir(
        (await Directory.systemTemp.createTemp('tsumige-groups-')).path);
    addTearDown(() => Directory(dir.root).deleteSync(recursive: true));
    resetBackupSessionForTest();
    final games = [game(const Uuid().v4(), 'Ep 1'), game(const Uuid().v4(), 'Ep 2')];
    final library = Library(
      games: games,
      dismissedGroupSuggestions: {'a,b', 'c,d'},
    );
    await saveLibrary(dir, LoadedLibrary(library: library));
    final saved = jsonDecode(await dir.libraryJson.readAsString())
        as Map<String, Object?>;
    expect(saved['dismissed_group_suggestions'], ['a,b', 'c,d']);
    final again = await loadLibrary(dir);
    expect(again.library.dismissedGroupSuggestions, {'a,b', 'c,d'});
  });

  test('no dismissed suggestions omits the key and loads empty', () async {
    final dir = DataDir(
        (await Directory.systemTemp.createTemp('tsumige-groups-')).path);
    addTearDown(() => Directory(dir.root).deleteSync(recursive: true));
    resetBackupSessionForTest();
    final id = const Uuid().v4();
    await dir.libraryJson.writeAsString(jsonEncode({
      'schema_version': 1,
      'games': [
        {'id': id, 'title': 'Solo'}
      ],
    }));
    final loaded = await loadLibrary(dir);
    expect(loaded.library.dismissedGroupSuggestions, isEmpty);
    await saveLibrary(dir, loaded);
    final saved = jsonDecode(await dir.libraryJson.readAsString())
        as Map<String, Object?>;
    expect(saved.containsKey('dismissed_group_suggestions'), isFalse);
  });

  test('short name strips the group name, full title when empty', () {
    final members = [
      game('a', '9-nine- Episode 1'),
      game('b', '9-nine- Episode 2'),
      game('c', '9-nine- NewEpisode'),
    ];
    final group = GameGroup(
        id: 'g', name: '9-nine-', memberIds: ['a', 'b', 'c']);
    final ids = byId(members);
    expect(memberShortName(group, members[0], ids), 'Episode 1');
    expect(memberShortName(group, members[2], ids), 'NewEpisode');
    final twins = [game('x', 'Same'), game('y', 'Same')];
    final twinGroup =
        GameGroup(id: 't', name: 'T', memberIds: ['x', 'y']);
    expect(memberShortName(twinGroup, twins[0], byId(twins)), 'Same');
  });
}
