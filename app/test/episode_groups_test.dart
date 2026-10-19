// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumige/main.dart';
import 'package:tsumige/src/core/covers.dart' as core;
import 'package:tsumige/src/core/groups.dart';
import 'package:tsumige/src/core/model.dart' as core;
import 'package:tsumige/src/core/paths.dart' as core;
import 'package:tsumige/src/core/vndb.dart' as core;
import 'package:tsumige/src/features/library/data/library_repository.dart';
import 'package:tsumige/src/features/library/domain/cover_source.dart';
import 'package:tsumige/src/features/library/domain/game_editor.dart';
import 'package:tsumige/src/features/library/domain/launch_actions.dart';
import 'package:tsumige/src/features/library/domain/selection.dart';
import 'package:tsumige/src/features/library/presentation/widgets/game_cover_tile.dart';
import 'package:tsumige/src/features/library/presentation/widgets/game_detail_pane.dart';
import 'package:tsumige/src/features/library/presentation/widgets/multi_selection_pane.dart';
import 'package:tsumige/src/utils/prefs/app_prefs.dart';
import 'package:tsumige/src/utils/prefs/prefs_mixin.dart';

class GroupFakeRepository implements LibraryRepository {
  GroupFakeRepository(this.loaded);

  final core.LoadedLibrary loaded;

  @override
  Future<core.LoadedLibrary> load() async => loaded;

  @override
  Future<void> save(core.LoadedLibrary value) async {
    normalizeGroups(value.library);
  }

  @override
  Future<core.VndbRefreshReport> refreshVndbData(
          core.LoadedLibrary loaded) async =>
      const core.VndbRefreshReport();

  @override
  Future<core.ThumbReport> ensureThumbnails(core.Library library) async =>
      core.ThumbReport();
}

core.Game game(String id, String title, {bool played = false}) => core.Game(
      id: id,
      title: title,
      playSessions: [
        if (played)
          core.PlaySession(
              startedAt: DateTime.utc(2026, 1, 1), durationSeconds: 10),
      ],
    );

core.LoadedLibrary groupLibrary({String? lastPickedId, bool firstPlayed = false}) {
  final ep1 = game('ep1', '9-nine- Episode 1', played: firstPlayed);
  final ep2 = game('ep2', '9-nine- Episode 2');
  final ep3 = game('ep3', '9-nine- NewEpisode');
  final library = core.Library(games: [
    ep1,
    ep2,
    ep3,
    game('solo-a', 'Solo A'),
    game('solo-b', 'Solo B'),
  ]);
  library.groups.add(core.GameGroup(
      id: 'gr1',
      name: '9-nine-',
      memberIds: ['ep1', 'ep2', 'ep3'],
      lastPickedId: lastPickedId));
  return core.LoadedLibrary(library: library);
}

Future<GroupFakeRepository> pumpGroups(
    WidgetTester tester, core.LoadedLibrary loaded) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('window_manager'),
    (call) async => call.method == 'isMaximized' ? false : null,
  );
  final temp = Directory.systemTemp.createTempSync('tsumige_groups_test_');
  addTearDown(() => temp.deleteSync(recursive: true));
  SharedPreferences.setMockInitialValues({});
  final fake = GroupFakeRepository(loaded);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
        libraryRepositoryProvider.overrideWithValue(fake),
        coverExistsProvider.overrideWithValue((_) => false),
        umuRunPathProvider.overrideWithValue('/usr/bin/umu-run'),
      ],
      child: const TsumigeApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
  return fake;
}

Finder paneText(String text) => find.descendant(
      of: find.byType(GameDetailPane),
      matching: find.text(text),
    );

Finder toolbarSearch() => find.descendant(
      of: find.byKey(const ValueKey('toolbar-search')),
      matching: find.byType(TextField),
    );

Future<void> ctrlClick(WidgetTester tester, Finder finder) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
  await tester.tap(finder);
  await tester.pump();
  await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
  await tester.pump();
}

Finder groupNameField() => find.descendant(
      of: find.byKey(const ValueKey('group-name-frame')),
      matching: find.byType(TextField),
    );

String groupNameFieldText(WidgetTester tester) =>
    tester.widget<TextField>(groupNameField()).controller!.text;

void main() {
  testWidgets('a 3-member group and 2 singles show 3 tiles', (tester) async {
    await pumpGroups(tester, groupLibrary(lastPickedId: 'ep1'));
    expect(find.byType(GameCoverTile), findsNWidgets(3));
    expect(find.text('9-nine-'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('9-nine- Episode 1'), findsNothing);
    expect(find.text('Solo A'), findsOneWidget);
    expect(find.text('Solo B'), findsOneWidget);
  });

  testWidgets('searching a member title shows the group tile', (tester) async {
    await pumpGroups(tester, groupLibrary(lastPickedId: 'ep1'));
    await tester.enterText(toolbarSearch(), 'Episode 2');
    await tester.pump();
    expect(find.byType(GameCoverTile), findsOneWidget);
    expect(find.text('9-nine-'), findsOneWidget);
  });

  testWidgets('selecting the group shows the remembered member', (tester) async {
    await pumpGroups(tester, groupLibrary(lastPickedId: 'ep3'));
    await tester.tap(find.text('9-nine-'));
    await tester.pump();
    await tester.pump();
    expect(paneText('9-nine- NewEpisode'), findsOneWidget);
  });

  testWidgets('with no lastPickedId it opens the first unplayed member',
      (tester) async {
    await pumpGroups(tester, groupLibrary(firstPlayed: true));
    await tester.tap(find.text('9-nine-'));
    await tester.pump();
    await tester.pump();
    expect(paneText('9-nine- Episode 2'), findsOneWidget);
  });

  testWidgets('the picker lists short names and picking switches the hero',
      (tester) async {
    final fake = await pumpGroups(tester, groupLibrary(lastPickedId: 'ep1'));
    await tester.tap(find.text('9-nine-'));
    await tester.pump();
    await tester.pump();
    expect(paneText('9-nine- Episode 1'), findsOneWidget);
    expect(paneText('Episode 1 · 1 of 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Choose episode'));
    await tester.pumpAndSettle();
    expect(find.text('Episode 1'), findsOneWidget);
    expect(find.text('Episode 2'), findsOneWidget);
    expect(find.text('NewEpisode'), findsOneWidget);
    await tester.tap(find.text('Episode 2'));
    await tester.pump();
    await tester.pump();
    expect(paneText('9-nine- Episode 2'), findsOneWidget);
    expect(fake.loaded.library.groups.single.lastPickedId, 'ep2');
  });

  testWidgets('opening a member from Related shows the group picker on it',
      (tester) async {
    final loaded = groupLibrary(lastPickedId: 'ep1');
    final games = loaded.library.games;
    final ep1 = games.firstWhere((g) => g.id == 'ep1');
    games
        .firstWhere((g) => g.id == 'ep2')
        .vndbId = 'v2';
    ep1.relations.add(
      const core.VnRelation(
        vndbId: 'v2',
        relation: 'seq',
        title: '9-nine- Episode 2',
        official: true,
      ),
    );
    final fake = await pumpGroups(tester, loaded);
    await tester.tap(find.text('9-nine-'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Related'));
    await tester.pumpAndSettle();
    final memberTile = find.text('9-nine- Episode 2');
    await tester.ensureVisible(memberTile);
    await tester.pumpAndSettle();
    await tester.tap(memberTile);
    await tester.pump();
    await tester.pump();
    expect(paneText('9-nine- Episode 2'), findsOneWidget);
    expect(paneText('Episode 2 · 2 of 3'), findsOneWidget);
    expect(fake.loaded.library.groups.single.lastPickedId, 'ep2');
  });

  testWidgets('removing the shown member keeps the group open', (tester) async {
    final fake = await pumpGroups(tester, groupLibrary(lastPickedId: 'ep1'));
    await tester.tap(find.text('9-nine-'));
    await tester.pump();
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GameDetailPane)),
    );
    await container.read(gameEditorProvider).remove('ep1');
    await tester.pump();
    await tester.pump();
    expect(fake.loaded.library.groups.single.memberIds, ['ep2', 'ep3']);
    expect(container.read(selectedGameIdProvider), 'gr1');
    expect(paneText('9-nine- Episode 2'), findsOneWidget);
  });

  testWidgets('removing down to one member dissolves the group and clears',
      (tester) async {
    final library = core.Library(games: [
      game('ep1', 'Duo Episode 1'),
      game('ep2', 'Duo Episode 2'),
    ]);
    library.groups.add(
      core.GameGroup(
          id: 'gr1',
          name: 'Duo',
          memberIds: ['ep1', 'ep2'],
          lastPickedId: 'ep1'),
    );
    final fake =
        await pumpGroups(tester, core.LoadedLibrary(library: library));
    await tester.tap(find.text('Duo'));
    await tester.pump();
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GameDetailPane)),
    );
    await container.read(gameEditorProvider).remove('ep1');
    await tester.pump();
    await tester.pump();
    expect(fake.loaded.library.groups, isEmpty);
    expect(container.read(selectedGameIdProvider), isNull);
    expect(find.byType(GameDetailPane), findsNothing);
  });

  testWidgets('ctrl+click two tiles combines them into a group of 2',
      (tester) async {
    final fake = await pumpGroups(tester, groupLibrary(lastPickedId: 'ep1'));
    await ctrlClick(tester, find.text('Solo A'));
    await ctrlClick(tester, find.text('Solo B'));
    expect(find.text('2 games selected'), findsOneWidget);
    await tester.tap(find.text('Combine into one tile…'));
    await tester.pumpAndSettle();
    expect(find.text('Combine into one tile'), findsOneWidget);
    expect(groupNameFieldText(tester), 'Solo');
    await tester.enterText(groupNameField(), 'Test');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('group-name-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Test'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(fake.loaded.library.groups, hasLength(2));
    final created = fake.loaded.library.groups
        .firstWhere((group) => group.id != 'gr1');
    expect(created.name, 'Test');
    expect(created.memberIds, hasLength(2));
  });

  testWidgets('shift+click selects the range', (tester) async {
    final library = core.Library(games: [
      game('a', 'Alpha'),
      game('b', 'Beta'),
      game('c', 'Gamma'),
      game('d', 'Delta'),
    ]);
    await pumpGroups(tester, core.LoadedLibrary(library: library));
    final tiles = find.byType(GameCoverTile);
    await tester.tap(tiles.first);
    await tester.pump();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.tap(tiles.last);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    expect(find.text('4 games selected'), findsOneWidget);
  });

  testWidgets('click then ctrl+click keeps the open tile selected',
      (tester) async {
    final fake = await pumpGroups(tester, groupLibrary(lastPickedId: 'ep1'));
    await tester.tap(find.text('Solo A'));
    await tester.pump();
    await tester.pump();
    await ctrlClick(tester, find.text('Solo B'));
    expect(find.text('2 games selected'), findsOneWidget);
    Finder paneRow(String text) => find.descendant(
          of: find.byType(MultiSelectionPane),
          matching: find.text(text),
        );
    expect(paneRow('Solo A'), findsOneWidget);
    expect(paneRow('Solo B'), findsOneWidget);
    await tester.tap(find.text('Combine into one tile…'));
    await tester.pumpAndSettle();
    await tester.enterText(groupNameField(), 'Pair');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('group-name-confirm')));
    await tester.pumpAndSettle();
    final created = fake.loaded.library.groups
        .firstWhere((group) => group.id != 'gr1');
    expect(created.memberIds.toSet(), {'solo-a', 'solo-b'});
  });

  testWidgets('searching away a selected tile opens the one left',
      (tester) async {
    await pumpGroups(tester, groupLibrary(lastPickedId: 'ep1'));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GameCoverTile).first),
    );
    await ctrlClick(tester, find.text('Solo A'));
    await ctrlClick(tester, find.text('Solo B'));
    expect(find.text('2 games selected'), findsOneWidget);
    await tester.enterText(toolbarSearch(), 'Solo A');
    await tester.pump();
    await tester.pump();
    expect(find.text('2 games selected'), findsNothing);
    expect(container.read(selectedGameIdProvider), 'solo-a');
    expect(paneText('Solo A'), findsOneWidget);
  });

  testWidgets('removing a selected game updates the panel', (tester) async {
    final fake = await pumpGroups(tester, groupLibrary(lastPickedId: 'ep1'));
    await ctrlClick(tester, find.text('Solo A'));
    await ctrlClick(tester, find.text('Solo B'));
    expect(find.text('2 games selected'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GameCoverTile).first),
    );
    await container.read(gameEditorProvider).remove('solo-a');
    await tester.pump();
    await tester.pump();
    expect(
      fake.loaded.library.games.any((game) => game.id == 'solo-a'),
      isFalse,
    );
    expect(find.text('2 games selected'), findsNothing);
    expect(container.read(selectedGameIdProvider), 'solo-b');
    expect(paneText('Solo B'), findsOneWidget);
  });

  testWidgets('shift+click with no anchor starts from the open tile',
      (tester) async {
    await pumpGroups(tester, groupLibrary(lastPickedId: 'ep1'));
    await tester.tap(find.text('Solo A'));
    await tester.pump();
    await tester.pump();
    await ctrlClick(tester, find.text('Solo B'));
    expect(find.text('2 games selected'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('2 games selected'), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.tap(find.text('Solo B'));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    expect(find.text('2 games selected'), findsOneWidget);
  });

  testWidgets('clear selection returns to the tile open before',
      (tester) async {
    await pumpGroups(tester, groupLibrary(lastPickedId: 'ep1'));
    await tester.tap(find.text('Solo A'));
    await tester.pump();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.tap(find.text('Solo B'));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    expect(find.text('2 games selected'), findsOneWidget);
    await tester.tap(find.text('Clear selection'));
    await tester.pump();
    await tester.pump();
    expect(find.text('2 games selected'), findsNothing);
    expect(paneText('Solo A'), findsOneWidget);
    expect(paneText('Solo B'), findsNothing);
  });

  testWidgets('combining a group with a game flattens into one group of 3',
      (tester) async {
    final library = core.Library(games: [
      game('ep1', 'Duo Episode 1'),
      game('ep2', 'Duo Episode 2'),
      game('s1', 'Lone Wolf'),
    ]);
    library.groups.add(
      core.GameGroup(id: 'gr1', name: 'Duo', memberIds: ['ep1', 'ep2']),
    );
    final fake =
        await pumpGroups(tester, core.LoadedLibrary(library: library));
    await ctrlClick(tester, find.text('Duo'));
    await ctrlClick(tester, find.text('Lone Wolf'));
    expect(find.text('2 games selected'), findsOneWidget);
    expect(find.text('Duo (2)'), findsOneWidget);
    await tester.tap(find.text('Combine into one tile…'));
    await tester.pumpAndSettle();
    expect(groupNameFieldText(tester), 'Duo Episode 1');
    await tester.enterText(groupNameField(), 'Trio');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('group-name-confirm')));
    await tester.pumpAndSettle();
    expect(fake.loaded.library.groups, hasLength(1));
    final group = fake.loaded.library.groups.single;
    expect(group.name, 'Trio');
    expect(group.id, isNot('gr1'));
    expect(group.memberIds, hasLength(3));
    expect(find.text('Trio'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('rename changes the tile name and the saved file',
      (tester) async {
    final fake = await pumpGroups(tester, groupLibrary(lastPickedId: 'ep1'));
    await tester.tap(find.text('9-nine-'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename group…'));
    await tester.pumpAndSettle();
    expect(groupNameFieldText(tester), '9-nine-');
    await tester.enterText(groupNameField(), 'Renamed');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('group-name-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Renamed'), findsOneWidget);
    expect(fake.loaded.library.groups.single.name, 'Renamed');
  });

  testWidgets('the name field is focused, selected, and Enter saves',
      (tester) async {
    final fake = await pumpGroups(tester, groupLibrary(lastPickedId: 'ep1'));
    await tester.tap(find.text('9-nine-'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename group…'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(groupNameField());
    expect(tester.binding.focusManager.primaryFocus, field.focusNode);
    expect(
      field.controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 7),
    );
    await tester.enterText(groupNameField(), 'X');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('X'), findsOneWidget);
    expect(fake.loaded.library.groups.single.name, 'X');
  });

  testWidgets('split restores separate tiles and drops the group',
      (tester) async {
    final fake = await pumpGroups(tester, groupLibrary(lastPickedId: 'ep1'));
    await tester.tap(find.text('9-nine-'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split into separate tiles'));
    await tester.pump();
    await tester.pump();
    expect(fake.loaded.library.groups, isEmpty);
    expect(find.byType(GameCoverTile), findsNWidgets(5));
    Finder gridText(String text) => find.descendant(
          of: find.byType(GameCoverTile),
          matching: find.text(text),
        );
    expect(gridText('9-nine- Episode 1'), findsOneWidget);
    expect(gridText('9-nine- Episode 2'), findsOneWidget);
    expect(gridText('9-nine- NewEpisode'), findsOneWidget);
    expect(paneText('9-nine- Episode 1'), findsOneWidget);
  });

  testWidgets('no suggestions means no notice', (tester) async {
    final library = core.Library(games: [
      game('a', 'Alpha'),
      game('b', 'Beta'),
    ]);
    await pumpGroups(tester, core.LoadedLibrary(library: library));
    expect(find.textContaining('can be grouped'), findsNothing);
    expect(find.text('Review'), findsNothing);
  });

  testWidgets('esc clears a multi-selection', (tester) async {
    await pumpGroups(tester, groupLibrary(lastPickedId: 'ep1'));
    await ctrlClick(tester, find.text('Solo A'));
    await ctrlClick(tester, find.text('Solo B'));
    expect(find.text('2 games selected'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('2 games selected'), findsNothing);
    expect(find.byType(GameDetailPane), findsNothing);
  });

  testWidgets('two suggestions show the notice and list both in Review',
      (tester) async {
    await pumpGroups(tester, suggestionLibrary());
    expect(
      find.text(
          '2 series in your library can be grouped into one tile each.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Group these into one tile each?'), findsOneWidget);
    expect(find.text('Alpha · 2 entries'), findsOneWidget);
    expect(find.text('Beta · 2 entries'), findsOneWidget);
    expect(find.text('Episode 1, Episode 2'), findsNWidgets(2));
    expect(
      find.text('They share a VNDB entry, and each title names a part.'),
      findsOneWidget,
    );
    expect(
      find.text(
          'VNDB lists them as a sequel chain, and each title names a part.'),
      findsOneWidget,
    );
  });

  testWidgets('Group creates the group and its tile', (tester) async {
    final fake = await pumpGroups(tester, suggestionLibrary());
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('suggest-group:a1,a2')));
    await tester.pumpAndSettle();
    expect(find.text('Alpha · 2 entries'), findsNothing);
    expect(find.text('Beta · 2 entries'), findsOneWidget);
    expect(fake.loaded.library.groups, hasLength(1));
    final created = fake.loaded.library.groups.single;
    expect(created.name, 'Alpha');
    expect(created.memberIds, hasLength(2));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    Finder gridText(String text) => find.descendant(
          of: find.byType(GameCoverTile),
          matching: find.text(text),
        );
    expect(gridText('Alpha'), findsOneWidget);
    expect(gridText('2'), findsOneWidget);
  });

  testWidgets('grouping the last suggestion closes Review by itself',
      (tester) async {
    await pumpGroups(tester, suggestionLibrary(beta: false));
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('suggest-group:a1,a2')));
    await tester.pumpAndSettle();
    expect(find.text('Group these into one tile each?'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('Not a series persists and the notice drops to 1',
      (tester) async {
    final fake = await pumpGroups(tester, suggestionLibrary());
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('suggest-dismiss:a1,a2')));
    await tester.pumpAndSettle();
    expect(find.text('Alpha · 2 entries'), findsNothing);
    expect(find.text('Beta · 2 entries'), findsOneWidget);
    expect(fake.loaded.library.dismissedGroupSuggestions, {'a1,a2'});
    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(
      find.text('1 series in your library can be grouped into one tile.'),
      findsOneWidget,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GameCoverTile).first),
    );
    await container.read(libraryProvider.notifier).reload();
    await tester.pump();
    await tester.pump();
    expect(
      find.text('1 series in your library can be grouped into one tile.'),
      findsOneWidget,
    );
  });

  testWidgets('Dismiss hides the notice until a new series appears',
      (tester) async {
    await pumpGroups(tester, suggestionLibrary(beta: false));
    expect(
      find.text('1 series in your library can be grouped into one tile.'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('can be grouped'), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GameCoverTile).first),
    );
    expect(container.read(dismissedSuggestionNoticeProvider), {'a1,a2'});
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('library.dismissedSuggestionNotice'),
      ['a1,a2'],
    );
    await container.read(gameEditorProvider).addAll([
      core.Game(
        id: 'b1',
        title: 'Beta Episode 1',
        vndbId: 'v2',
        relations: [seqRelation('v3')],
      ),
      core.Game(id: 'b2', title: 'Beta Episode 2', vndbId: 'v3'),
    ]);
    await tester.pump();
    await tester.pump();
    expect(
      find.text(
          '2 series in your library can be grouped into one tile each.'),
      findsOneWidget,
    );
  });
}

core.VnRelation seqRelation(String vndbId) => core.VnRelation(
      vndbId: vndbId,
      relation: 'seq',
      title: '',
      official: true,
    );

/// Two suggestable series: Alpha shares one VNDB id, Beta is a sequel chain.
core.LoadedLibrary suggestionLibrary({bool beta = true}) {
  final games = [
    core.Game(id: 'a1', title: 'Alpha Episode 1', vndbId: 'v9'),
    core.Game(id: 'a2', title: 'Alpha Episode 2', vndbId: 'v9'),
    if (beta)
      core.Game(
        id: 'b1',
        title: 'Beta Episode 1',
        vndbId: 'v2',
        relations: [seqRelation('v3')],
      ),
    if (beta) core.Game(id: 'b2', title: 'Beta Episode 2', vndbId: 'v3'),
  ];
  return core.LoadedLibrary(library: core.Library(games: games));
}
