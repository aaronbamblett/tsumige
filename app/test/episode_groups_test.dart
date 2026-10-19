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
import 'package:tsumige/src/features/library/domain/launch_actions.dart';
import 'package:tsumige/src/features/library/presentation/widgets/game_cover_tile.dart';
import 'package:tsumige/src/features/library/presentation/widgets/game_detail_pane.dart';
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
      name: 'Nine Nine',
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

void main() {
  testWidgets('a 3-member group and 2 singles show 3 tiles', (tester) async {
    await pumpGroups(tester, groupLibrary(lastPickedId: 'ep1'));
    expect(find.byType(GameCoverTile), findsNWidgets(3));
    expect(find.text('Nine Nine'), findsOneWidget);
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
    expect(find.text('Nine Nine'), findsOneWidget);
  });

  testWidgets('selecting the group shows the remembered member', (tester) async {
    await pumpGroups(tester, groupLibrary(lastPickedId: 'ep3'));
    await tester.tap(find.text('Nine Nine'));
    await tester.pump();
    await tester.pump();
    expect(paneText('9-nine- NewEpisode'), findsOneWidget);
  });

  testWidgets('with no lastPickedId it opens the first unplayed member',
      (tester) async {
    await pumpGroups(tester, groupLibrary(firstPlayed: true));
    await tester.tap(find.text('Nine Nine'));
    await tester.pump();
    await tester.pump();
    expect(paneText('9-nine- Episode 2'), findsOneWidget);
  });

  testWidgets('the picker lists short names and picking switches the hero',
      (tester) async {
    final fake = await pumpGroups(tester, groupLibrary(lastPickedId: 'ep1'));
    await tester.tap(find.text('Nine Nine'));
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

  testWidgets('split restores separate tiles and drops the group',
      (tester) async {
    final fake = await pumpGroups(tester, groupLibrary(lastPickedId: 'ep1'));
    await tester.tap(find.text('Nine Nine'));
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
}
