// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vnl/main.dart';
import 'package:vnl/src/core/covers.dart' as core;
import 'package:vnl/src/core/model.dart' as core;
import 'package:vnl/src/core/paths.dart' as core;
import 'package:vnl/src/core/vndb.dart' as core;
import 'package:vnl/src/features/library/data/library_repository.dart';
import 'package:vnl/src/features/library/domain/cover_source.dart';
import 'package:vnl/src/features/library/presentation/widgets/game_detail_pane.dart';
import 'package:vnl/src/utils/prefs/prefs_mixin.dart';

class DetailFakeRepository implements LibraryRepository {
  DetailFakeRepository(this.games);

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

void setSurface(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> pumpLibrary(WidgetTester tester, List<core.Game> games,
    {double width = 1280, double height = 800}) async {
  setSurface(tester, width, height);
  final temp = Directory.systemTemp.createTempSync('vnl_detail_test_');
  addTearDown(() => temp.deleteSync(recursive: true));
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider
          .overrideWithValue(await SharedPreferences.getInstance()),
      dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
      libraryRepositoryProvider
          .overrideWithValue(DetailFakeRepository(games)),
      coverExistsProvider.overrideWithValue((_) => false),
    ],
    child: const VnlApp(),
  ));
  await tester.pump();
  await tester.pump();
}

Future<void> openPane(WidgetTester tester, String title) async {
  await tester.tap(find.text(title).first);
  await tester.pump();
  await tester.pump();
}

Finder paneText(WidgetTester tester, String text) => find.descendant(
      of: find.byType(GameDetailPane),
      matching: find.text(text),
    );

Finder tabLabel(String text) => find.descendant(
      of: find.byType(TabBar),
      matching: find.text(text),
    );

Finder richPaneText(WidgetTester tester, String text) => find.descendant(
      of: find.byType(GameDetailPane),
      matching: find.textContaining(text, findRichText: true),
    );

Future<void> openTab(WidgetTester tester, String text) async {
  await tester.tap(tabLabel(text));
  await tester.pumpAndSettle();
}

void _visitSpans(
    InlineSpan span, TextStyle? inherited, void Function(TextSpan, TextStyle?) fn) {
  if (span is TextSpan) {
    final current = inherited == null
        ? span.style
        : (span.style == null ? inherited : inherited.merge(span.style));
    fn(span, current);
    for (final child in span.children ?? const <InlineSpan>[]) {
      _visitSpans(child, current, fn);
    }
  }
}

TextStyle? spoilerSpanStyle(WidgetTester tester, String secret) {
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    var seen = false;
    TextStyle? result;
    _visitSpans(rich.text, null, (span, style) {
      if (span.text != null && span.text!.contains(secret)) {
        seen = true;
        result = style;
      }
    });
    if (seen) return result;
  }
  return null;
}

Future<void> tapSpoilerText(WidgetTester tester, String secret) async {
  RichText? target;
  for (final element in find.byType(RichText).evaluate()) {
    _visitSpans((element.widget as RichText).text, null, (span, _) {
      if (span.text != null && span.text!.contains(secret)) {
        target = element.widget as RichText;
      }
    });
  }
  expect(target, isNotNull);
  final paragraph =
      tester.renderObject<RenderParagraph>(find.byWidget(target!));
  final plain = target!.text.toPlainText();
  final start = plain.indexOf(secret);
  expect(start, greaterThanOrEqualTo(0));
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + 1),
  );
  expect(boxes, isNotEmpty);
  await tester.tapAt(paragraph.localToGlobal(boxes.first.toRect().center));
  await tester.pump();
}

void main() {
  Finder findToolbarSearch() => find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == 'Search',
      );

  testWidgets('spoiler text is hidden until tapped, then shown',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(
          id: 'g1',
          title: 'Alpha',
          description: 'before [spoiler]secretwords[/spoiler] after'),
    ]);
    await openPane(tester, 'Alpha');
    final hidden = spoilerSpanStyle(tester, 'secretwords');
    expect(hidden?.backgroundColor, isNotNull);
    expect(hidden?.backgroundColor, hidden?.color);
    await tapSpoilerText(tester, 'secretwords');
    expect(find.textContaining('secretwords', findRichText: true),
        findsOneWidget);
    expect(spoilerSpanStyle(tester, 'secretwords')?.backgroundColor, isNull);
  });

  testWidgets('hero shows the title inside the hero area', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    final heroRect =
        tester.getRect(find.byKey(const ValueKey('detail-hero')));
    final titleRect = tester.getRect(paneText(tester, 'Alpha'));
    expect(heroRect.contains(titleRect.topLeft), isTrue);
    expect(heroRect.contains(titleRect.bottomRight), isTrue);
  });

  testWidgets('hero without a cover is a 120px block', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    final heroRect =
        tester.getRect(find.byKey(const ValueKey('detail-hero')));
    expect(heroRect.height, moreOrLessEquals(120, epsilon: 0.5));
  });

  testWidgets('the four tabs exist and Launch shows Mode', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    for (final label in ['Info', 'Launch', 'Routes', 'History']) {
      expect(tabLabel(label), findsOneWidget);
    }
    expect(find.text('Mode'), findsNothing);
    await openTab(tester, 'Launch');
    expect(find.text('Mode'), findsOneWidget);
  });

  testWidgets('history shows Not played yet with no sessions',
      (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'History');
    expect(find.text('TOTAL PLAYTIME'), findsOneWidget);
    expect(find.text('0 min'), findsOneWidget);
    expect(find.text('SESSIONS'), findsOneWidget);
    expect(find.text('Not played yet'), findsOneWidget);
  });

  testWidgets('history lists the newer session first', (tester) async {
    final older = DateTime.utc(2024, 1, 2, 10, 0);
    final newer = DateTime.utc(2024, 3, 4, 12, 30);
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', playSessions: [
        core.PlaySession(startedAt: older, durationSeconds: 180),
        core.PlaySession(startedAt: newer, durationSeconds: 120),
      ]),
    ]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'History');
    final format = DateFormat('yyyy-MM-dd HH:mm');
    final newerText = find.textContaining(format.format(newer.toLocal()));
    final olderText = find.textContaining(format.format(older.toLocal()));
    expect(newerText, findsOneWidget);
    expect(olderText, findsOneWidget);
    expect(tester.getTopLeft(newerText).dy,
        lessThan(tester.getTopLeft(olderText).dy));
  });

  testWidgets('info tab shows rating, tags and description labels',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(
        id: 'g1',
        title: 'Alpha',
        description: 'A story',
        released: '2024-05-06',
        vndbRating: 85.0,
        vndbVotecount: 12,
        tags: ['Action', 'Romance'],
      ),
    ]);
    await openPane(tester, 'Alpha');
    expect(paneText(tester, 'VNDB RATING'), findsOneWidget);
    expect(richPaneText(tester, '8.5'), findsOneWidget);
    expect(richPaneText(tester, '12 votes'), findsOneWidget);
    expect(paneText(tester, 'RELEASED'), findsOneWidget);
    expect(find.text('2024-05-06'), findsOneWidget);
    expect(paneText(tester, 'TAGS'), findsOneWidget);
    expect(paneText(tester, 'Action'), findsOneWidget);
    expect(paneText(tester, 'Romance'), findsOneWidget);
    expect(paneText(tester, 'DESCRIPTION'), findsOneWidget);
  });

  testWidgets('fifteen tags wrap without overflow at panel width 400',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(
        id: 'g1',
        title: 'Alpha',
        tags: [
          for (var i = 0; i < 15; i++) 'Extremely long tag number $i',
        ],
      ),
    ]);
    await openPane(tester, 'Alpha');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(paneText(tester, 'Extremely long tag number 14'),
        findsOneWidget);
  });

  testWidgets('changing the game resets the tab to Info', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', description: 'Alpha story'),
      core.Game(id: 'g2', title: 'Beta', description: 'Beta story'),
    ]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'Launch');
    expect(find.text('Mode'), findsOneWidget);
    await tester.tap(find.text('Beta').first);
    await tester.pump();
    await tester.pump();
    final tabContext = tester.element(find.byType(TabBar));
    expect(DefaultTabController.of(tabContext).index, 0);
    expect(find.text('Mode'), findsNothing);
    expect(find.text('Beta story'), findsOneWidget);
  });

  testWidgets('launch button is pinned below a long description',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(
          id: 'g1', title: 'Alpha', description: 'A very long tale. ' * 500),
    ]);
    await openPane(tester, 'Alpha');
    final launch = find.widgetWithText(FilledButton, 'Launch');
    expect(launch, findsOneWidget);
    expect(tester.widget<FilledButton>(launch).onPressed, isNull);
    final launchRect = tester.getRect(launch);
    expect(launchRect.top, greaterThanOrEqualTo(0));
    expect(launchRect.bottom, lessThanOrEqualTo(800));
    expect(find.byTooltip('Launching arrives in the next build'),
        findsNWidgets(2));
  });

  testWidgets('run exe button is absent for a Native game', (tester) async {
    await pumpLibrary(tester, [
      core.Game(
          id: 'g1',
          title: 'Alpha',
          launch: core.LaunchOverrides(mode: core.LaunchMode.native)),
    ]);
    await openPane(tester, 'Alpha');
    expect(
        find.widgetWithText(OutlinedButton, 'Run .exe inside prefix'),
        findsNothing);
    expect(find.widgetWithText(FilledButton, 'Launch'), findsOneWidget);
  });

  testWidgets('run exe button shows for a Proton game', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    expect(find.widgetWithText(OutlinedButton, 'Run .exe inside prefix'),
        findsOneWidget);
  });

  testWidgets('launch tab falls back to global defaults', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'Launch');
    expect(find.textContaining('Proton', findRichText: true), findsOneWidget);
    expect(find.textContaining('default', findRichText: true),
        findsWidgets);
    expect(find.text('Prefix'), findsOneWidget);
    expect(find.text('Runner'), findsOneWidget);
    expect(find.textContaining('umu default', findRichText: true), findsOneWidget);
  });

  testWidgets('steam mode shows only the app id', (tester) async {
    await pumpLibrary(tester, [
      core.Game(
          id: 'g1',
          title: 'Alpha',
          launch: core.LaunchOverrides(
              mode: core.LaunchMode.steam, steamAppId: 123)),
    ]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'Launch');
    expect(find.text('Steam app id'), findsOneWidget);
    expect(find.textContaining('123', findRichText: true), findsOneWidget);
    expect(find.text('Mode'), findsNothing);
    expect(find.text('Prefix'), findsNothing);
  });

  testWidgets('native mode shows only executable and arguments',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(
          id: 'g1',
          title: 'Alpha',
          launch: core.LaunchOverrides(
              mode: core.LaunchMode.native,
              executable: '/games/alpha/run.sh',
              arguments: '--full')),
    ]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'Launch');
    expect(find.text('Executable'), findsOneWidget);
    expect(find.text('/games/alpha/run.sh'), findsOneWidget);
    expect(find.text('Arguments'), findsOneWidget);
    expect(find.textContaining('--full', findRichText: true), findsOneWidget);
    expect(find.text('Prefix'), findsNothing);
    expect(find.text('Runner'), findsNothing);
  });

  testWidgets('long executable truncates with a full-path tooltip',
      (tester) async {
    final path =
        '/very/long/prefix/drive_c/Program Files/Visual Novels/Alpha Game/game/alpha-visual-novel-launcher.exe';
    await pumpLibrary(tester, [
      core.Game(
          id: 'g1',
          title: 'Alpha',
          launch: core.LaunchOverrides(executable: path)),
    ]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'Launch');
    expect(find.byTooltip(path), findsOneWidget);
    expect(find.text(path), findsNothing);
  });

  testWidgets('routes tab shows completion and the active label',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', activeRoute: 'Rin', routes: [
        core.Route(name: 'Rin', completed: true),
        core.Route(name: 'Saber', completed: false),
      ]),
    ]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'Routes');
    expect(find.text('Rin'), findsOneWidget);
    expect(find.text('Saber'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('routes tab shows No routes when empty', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'Routes');
    expect(find.text('No routes'), findsOneWidget);
  });

  testWidgets('tapping a tile opens the pane; Escape closes it',
      (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await tester.tap(find.text('Alpha').first);
    await tester.pump();
    await tester.pump();
    expect(find.text('Alpha'), findsNWidgets(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('search field is at least 240 wide at 1280', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    final searchBox = findToolbarSearch();
    final width = tester.getSize(searchBox).width;
    expect(width, greaterThanOrEqualTo(240));
    expect(width, lessThanOrEqualTo(360));
  });

  testWidgets('toolbar has no overflow at 480 and 1920', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')],
        width: 480);
    await tester.pump();
    expect(tester.takeException(), isNull);
    setSurface(tester, 1920, 800);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter hiding the selected game keeps the pane open',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha'),
      core.Game(id: 'g2', title: 'Beta'),
    ]);
    await openPane(tester, 'Alpha');
    await tester.enterText(findToolbarSearch(), 'zzz');
    await tester.pump();
    expect(find.text('0 of 2'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('close button clears the selection', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    expect(find.text('Alpha'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('selected tile uses the primary colour outline',
      (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    final cover = find.byKey(const ValueKey('cover-g1'));
    final frame = find.descendant(
      of: cover,
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration,
      ),
    );
    final decoration =
        (tester.widget<Container>(frame).decoration as BoxDecoration);
    final border = decoration.border as Border;
    final primary = Theme.of(tester.element(cover)).colorScheme.primary;
    expect(border.top.color, primary);
    expect(border.top.width, 3);
  });

  testWidgets('rating without a votecount shows no votes fallback',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', vndbRating: 85.0),
    ]);
    await openPane(tester, 'Alpha');
    expect(paneText(tester, 'VNDB RATING'), findsOneWidget);
    expect(richPaneText(tester, '8.5'), findsOneWidget);
    expect(find.textContaining('votes'), findsNothing);
  });

  testWidgets('release shows the RELEASED label', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', released: '2021-08-26'),
    ]);
    await openPane(tester, 'Alpha');
    expect(find.text('RELEASED'), findsOneWidget);
    expect(find.text('2021-08-26'), findsOneWidget);
  });

  testWidgets('empty game shows no info sections', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    expect(find.text('DESCRIPTION'), findsNothing);
    expect(find.text('TAGS'), findsNothing);
    expect(find.text('VNDB RATING'), findsNothing);
  });

  testWidgets('rating value divides by ten', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', vndbRating: 64),
    ]);
    await openPane(tester, 'Alpha');
    expect(richPaneText(tester, '6.4'), findsOneWidget);
  });
}
