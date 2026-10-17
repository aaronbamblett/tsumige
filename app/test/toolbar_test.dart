// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vnl/main.dart';
import 'package:vnl/src/constants/pref_keys.dart' as keys;
import 'package:vnl/src/core/covers.dart' as core;
import 'package:vnl/src/core/model.dart' as core;
import 'package:vnl/src/core/paths.dart' as core;
import 'package:vnl/src/core/vndb.dart' as core;
import 'package:vnl/src/features/library/data/library_repository.dart';
import 'package:vnl/src/features/library/domain/cover_source.dart';
import 'package:vnl/src/features/library/presentation/widgets/library_toolbar.dart';
import 'package:vnl/src/utils/prefs/app_prefs.dart';
import 'package:vnl/src/utils/prefs/prefs_mixin.dart';
import 'package:vnl/src/widgets/desktop/desktop_window_scaffold.dart';

class ToolbarFakeRepository implements LibraryRepository {
  ToolbarFakeRepository(this.games);

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

Future<void> pumpToolbar(WidgetTester tester, List<core.Game> games) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('window_manager'),
    (call) async {
      if (call.method == 'isMaximized') return false;
      return null;
    },
  );
  final temp = Directory.systemTemp.createTempSync('vnl_toolbar_test_');
  addTearDown(() => temp.deleteSync(recursive: true));
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider
          .overrideWithValue(await SharedPreferences.getInstance()),
      dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
      libraryRepositoryProvider.overrideWithValue(
        ToolbarFakeRepository(games),
      ),
      coverExistsProvider.overrideWithValue((_) => false),
    ],
    child: const VnlApp(),
  ));
  await tester.pump();
  await tester.pump();
}

List<core.Game> taggedGames() => [
      core.Game(id: 'g1', title: 'Alpha', tags: ['Romance']),
      core.Game(id: 'g2', title: 'Beta', tags: ['Action']),
    ];

void main() {
  testWidgets('sort and tag dropdowns are labelled', (tester) async {
    await pumpToolbar(tester, taggedGames());
    final sortMenu = tester.widget<DropdownMenu<keys.SortField>>(
      find.byType(DropdownMenu<keys.SortField>),
    );
    final tagMenu = tester.widget<DropdownMenu<String?>>(
      find.byType(DropdownMenu<String?>),
    );
    expect((sortMenu.label as Text).data, 'Sort by');
    expect((tagMenu.label as Text).data, 'Tag');
  });

  Finder findSearchField() => find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == 'Search');

  testWidgets('search field draws one complete rounded border',
      (tester) async {
    await pumpToolbar(tester, taggedGames());
    expect(findSearchField(), findsOneWidget);
    final decorator = tester.widget<InputDecorator>(
      find.descendant(
        of: findSearchField(),
        matching: find.byType(InputDecorator),
      ).first,
    );
    final border = decorator.decoration.border;
    expect(border, isA<OutlineInputBorder>());
    expect(
      (border as OutlineInputBorder).borderRadius,
      const BorderRadius.all(Radius.circular(12)),
    );
    expect(
      find.ancestor(
        of: findSearchField(),
        matching: find.byType(ClipRRect),
      ),
      findsNothing,
    );
  });

  testWidgets('sort and tag dropdowns use dropdown arrows', (tester) async {
    await pumpToolbar(tester, taggedGames());
    final sortMenu = tester.widget<DropdownMenu<keys.SortField>>(
      find.byType(DropdownMenu<keys.SortField>),
    );
    final tagMenu = tester.widget<DropdownMenu<String?>>(
      find.byType(DropdownMenu<String?>),
    );
    expect(
      (sortMenu.trailingIcon as Icon).icon,
      Icons.arrow_drop_down_rounded,
    );
    expect(
      (tagMenu.trailingIcon as Icon).icon,
      Icons.arrow_drop_down_rounded,
    );
  });

  testWidgets('choosing Title sets the sort field', (tester) async {
    await pumpToolbar(tester, taggedGames());
    await tester.tap(find.byType(DropdownMenu<keys.SortField>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title').last);
    await tester.pump();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryToolbar)));
    expect(container.read(sortFieldProvider), keys.SortField.title);
  });

  testWidgets('choosing a tag filters, All tags clears', (tester) async {
    await pumpToolbar(tester, taggedGames());
    final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryToolbar)));
    await tester.tap(find.byType(DropdownMenu<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Romance').last);
    await tester.pump();
    expect(container.read(tagFilterProvider), 'Romance');
    await tester.tap(find.byType(DropdownMenu<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All tags').last);
    await tester.pump();
    expect(container.read(tagFilterProvider), isNull);
  });

  testWidgets('search, sort and tag share one height', (tester) async {
    await pumpToolbar(tester, taggedGames());
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    final heights = [
      for (var i = 0; i < 3; i++) tester.getSize(fields.at(i)).height,
    ];
    expect(
      heights.reduce(max) - heights.reduce(min),
      lessThanOrEqualTo(1.0),
    );
  });

  testWidgets('no toolbar overflow at 480, 1280 and 1920 wide',
      (tester) async {
    await pumpToolbar(tester, taggedGames());
    for (final width in [480.0, 1280.0, 1920.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('window scaffold wraps the app', (tester) async {
    await pumpToolbar(tester, taggedGames());
    expect(find.byType(DesktopWindowScaffold), findsOneWidget);
    final context = tester.element(find.byType(DesktopWindowScaffold));
    expect(
      vnlRouterBuilder(context, const SizedBox()),
      isA<DesktopWindowScaffold>(),
    );
  });
}
