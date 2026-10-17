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
import 'package:vnl/main.dart';
import 'package:vnl/src/core/covers.dart' as core;
import 'package:vnl/src/core/model.dart' as core;
import 'package:vnl/src/core/paths.dart' as core;
import 'package:vnl/src/core/vndb.dart' as core;
import 'package:vnl/src/features/library/data/library_repository.dart';
import 'package:vnl/src/features/library/domain/cover_source.dart';
import 'package:vnl/src/utils/prefs/prefs_mixin.dart';

class RoutesFakeRepository implements LibraryRepository {
  RoutesFakeRepository(this.games);

  final List<core.Game> games;

  @override
  Future<core.LoadedLibrary> load() async =>
      core.LoadedLibrary(library: core.Library(games: games));

  @override
  Future<void> save(core.LoadedLibrary loaded) async {}

  @override
  Future<core.RatingReport> refreshRatings(core.LoadedLibrary loaded) async =>
      const core.RatingReport();

  @override
  Future<core.ThumbReport> ensureThumbnails(core.Library library) async =>
      core.ThumbReport();
}

Future<RoutesFakeRepository> pumpRoutes(
    WidgetTester tester, List<core.Game> games) async {
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
  final temp = Directory.systemTemp.createTempSync('vnl_routes_tab_test_');
  addTearDown(() => temp.deleteSync(recursive: true));
  SharedPreferences.setMockInitialValues({});
  final fake = RoutesFakeRepository(games);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider
          .overrideWithValue(await SharedPreferences.getInstance()),
      dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
      libraryRepositoryProvider.overrideWithValue(fake),
      coverExistsProvider.overrideWithValue((_) => false),
    ],
    child: const VnlApp(),
  ));
  await tester.pump();
  await tester.pump();
  return fake;
}

Future<void> openRoutes(WidgetTester tester, String title) async {
  await tester.tap(find.text(title).first);
  await tester.pump();
  await tester.pump();
  await tester.tap(find.descendant(
    of: find.byType(TabBar),
    matching: find.text('Routes'),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('add, with the blank and duplicate errors', (tester) async {
    final repo = await pumpRoutes(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openRoutes(tester, 'Alpha');
    expect(find.text('0 routes'), findsOneWidget);

    await tester.tap(find.byKey(const Key('routes-add')));
    await tester.pump();
    expect(find.text('Route name is required.'), findsOneWidget);
    expect(repo.games.first.routes, isEmpty);

    await tester.enterText(find.byKey(const Key('routes-new-name')), 'Rin');
    await tester.tap(find.byKey(const Key('routes-add')));
    await tester.pump();
    await tester.pump();
    expect(repo.games.first.routes.map((r) => r.name), ['Rin']);
    expect(find.text('1 routes'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('routes-new-name')), 'rin');
    await tester.tap(find.byKey(const Key('routes-add')));
    await tester.pump();
    expect(find.text('That route already exists.'), findsOneWidget);
    expect(repo.games.first.routes, hasLength(1));
  });

  testWidgets('complete toggle', (tester) async {
    final repo = await pumpRoutes(tester, [
      core.Game(id: 'g1', title: 'Alpha', routes: [core.Route(name: 'Rin')]),
    ]);
    await openRoutes(tester, 'Alpha');
    final box = find.byKey(const ValueKey('route-completed-Rin'));
    expect(tester.widget<Checkbox>(box).value, isFalse);
    await tester.tap(box);
    await tester.pump();
    await tester.pump();
    expect(repo.games.first.routes.first.completed, isTrue);
  });

  testWidgets('active dropdown', (tester) async {
    final repo = await pumpRoutes(tester, [
      core.Game(id: 'g1', title: 'Alpha', routes: [
        core.Route(name: 'Rin'),
        core.Route(name: 'Saber'),
      ]),
    ]);
    await openRoutes(tester, 'Alpha');
    await tester.tap(find.byKey(const Key('routes-active')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saber').last);
    await tester.pumpAndSettle();
    expect(repo.games.first.activeRoute, 'Saber');
  });

  testWidgets('rename updates activeRoute', (tester) async {
    final repo = await pumpRoutes(tester, [
      core.Game(id: 'g1', title: 'Alpha', activeRoute: 'Rin', routes: [
        core.Route(name: 'Rin'),
      ]),
    ]);
    await openRoutes(tester, 'Alpha');
    await tester.tap(find.byKey(const ValueKey('route-rename-Rin')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('route-rename-field')), 'Rin2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();
    expect(repo.games.first.routes.map((r) => r.name), ['Rin2']);
    expect(repo.games.first.activeRoute, 'Rin2');
  });

  testWidgets('deleting a completed route asks first', (tester) async {
    final repo = await pumpRoutes(tester, [
      core.Game(id: 'g1', title: 'Alpha', routes: [
        core.Route(name: 'Rin', completed: true),
      ]),
    ]);
    await openRoutes(tester, 'Alpha');
    await tester.tap(find.byKey(const ValueKey('route-delete-Rin')));
    await tester.pumpAndSettle();
    expect(find.text("Delete route Rin? It's marked completed."),
        findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.games.first.routes, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('route-delete-Rin')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(repo.games.first.routes, isEmpty);
  });

  testWidgets('an uncompleted route deletes immediately', (tester) async {
    final repo = await pumpRoutes(tester, [
      core.Game(id: 'g1', title: 'Alpha', routes: [
        core.Route(name: 'Rin'),
      ]),
    ]);
    await openRoutes(tester, 'Alpha');
    await tester.tap(find.byKey(const ValueKey('route-delete-Rin')));
    await tester.pump();
    await tester.pump();
    expect(repo.games.first.routes, isEmpty);
    expect(find.text("Delete route Rin? It's marked completed."),
        findsNothing);
  });

  testWidgets('deleting the active route clears it', (tester) async {
    final repo = await pumpRoutes(tester, [
      core.Game(id: 'g1', title: 'Alpha', activeRoute: 'Rin', routes: [
        core.Route(name: 'Rin'),
      ]),
    ]);
    await openRoutes(tester, 'Alpha');
    await tester.tap(find.byKey(const ValueKey('route-delete-Rin')));
    await tester.pump();
    await tester.pump();
    expect(repo.games.first.routes, isEmpty);
    expect(repo.games.first.activeRoute, isNull);
  });
}
