// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumige/main.dart';
import 'package:tsumige/src/core/covers.dart' as core;
import 'package:tsumige/src/core/model.dart' as core;
import 'package:tsumige/src/core/paths.dart' as core;
import 'package:tsumige/src/core/vndb.dart' as core;
import 'package:tsumige/src/core/store.dart';
import 'package:tsumige/src/features/library/data/library_repository.dart';
import 'package:tsumige/src/features/library/domain/cover_source.dart';
import 'package:tsumige/src/features/library/domain/game_editor.dart';
import 'package:tsumige/src/features/library/presentation/widgets/game_detail_pane.dart';
import 'package:tsumige/src/utils/prefs/prefs_mixin.dart';

Finder paneField(WidgetTester tester) => find.descendant(
      of: find.byType(GameDetailPane),
      matching: find.byWidgetPredicate((w) =>
          w is TextField && w.key != const ValueKey('notes-field')),
    );

class EditorFakeRepository implements LibraryRepository {
  EditorFakeRepository(this.games);

  final List<core.Game> games;
  int loads = 0;
  int saves = 0;
  Future<void> Function(core.LoadedLibrary)? onSave;

  @override
  Future<core.LoadedLibrary> load() async {
    loads++;
    return core.LoadedLibrary(library: core.Library(games: games));
  }

  @override
  Future<void> save(core.LoadedLibrary loaded) async {
    saves++;
    final hook = onSave;
    if (hook != null) await hook(loaded);
  }

  @override
  Future<core.VndbRefreshReport> refreshVndbData(core.LoadedLibrary loaded) async =>
      const core.VndbRefreshReport();

  @override
  Future<core.ThumbReport> ensureThumbnails(core.Library library) async =>
      core.ThumbReport();
}

Future<EditorFakeRepository> pumpEditorLibrary(
    WidgetTester tester, List<core.Game> games) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final temp = Directory.systemTemp.createTempSync('tsumige_editor_test_');
  addTearDown(() => temp.deleteSync(recursive: true));
  SharedPreferences.setMockInitialValues({});
  final fake = EditorFakeRepository(games);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider
          .overrideWithValue(await SharedPreferences.getInstance()),
      dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
      libraryRepositoryProvider.overrideWithValue(fake),
      coverExistsProvider.overrideWithValue((_) => false),
    ],
    child: const TsumigeApp(),
  ));
  await tester.pump();
  await tester.pump();
  return fake;
}

BuildContext appContext(WidgetTester tester) =>
    tester.element(find.text('Alpha').first);

void main() {
  testWidgets('update saves through the repository', (tester) async {
    final fake = await pumpEditorLibrary(
        tester, [core.Game(id: 'g1', title: 'Alpha')]);
    final context = appContext(tester);
    await ProviderScope.containerOf(context)
        .read(gameEditorProvider)
        .update('g1', (g) => g.favourite = true, context: context);
    await tester.pumpAndSettle();
    expect(fake.saves, 1);
    expect(fake.games.single.favourite, isTrue);
  });

  testWidgets('ChangedOnDisk reloads and shows the toast', (tester) async {
    final fake = await pumpEditorLibrary(
        tester, [core.Game(id: 'g1', title: 'Alpha')]);
    fake.onSave = (_) async => throw const ChangedOnDisk('library.json');
    final context = appContext(tester);
    final loadsBefore = fake.loads;
    await ProviderScope.containerOf(context)
        .read(gameEditorProvider)
        .update('g1', (g) => g.favourite = true, context: context);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(fake.loads, greaterThan(loadsBefore));
    expect(find.text(changedOnDiskMessage), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a blur-save after switching games writes to the original game',
      (tester) async {
    await pumpEditorLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', description: 'old words'),
      core.Game(id: 'g2', title: 'Beta', description: 'beta words'),
    ]);
    final container =
        ProviderScope.containerOf(tester.element(find.text('Alpha').first));
    await tester.tap(find.text('Alpha').first);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip('Edit description'));
    await tester.pump();
    await tester.enterText(paneField(tester), 'new words');
    await tester.pump();
    await tester.tap(find.text('Beta').first);
    await tester.pumpAndSettle();
    final games = container.read(libraryProvider).value!.library.games;
    expect(games.firstWhere((g) => g.id == 'g1').description, 'new words');
    expect(games.firstWhere((g) => g.id == 'g2').description, 'beta words');
  });
}
