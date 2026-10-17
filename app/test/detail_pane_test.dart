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

/// Effective declared style of the span holding [secret], or null when the
/// spoiler is revealed (no hiding style declared anywhere above the text).
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

  testWidgets('a game with no sessions shows 0 min and no session rows',
      (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    expect(find.textContaining('0 min'), findsOneWidget);
    expect(
        find.textContaining(RegExp(r'\d{4}-\d{2}-\d{2}')), findsNothing);
  });

  testWidgets('a game with two sessions lists the newer one first',
      (tester) async {
    final older = DateTime.utc(2024, 1, 2, 10, 0);
    final newer = DateTime.utc(2024, 3, 4, 12, 30);
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', playSessions: [
        core.PlaySession(startedAt: older, durationSeconds: 180),
        core.PlaySession(startedAt: newer, durationSeconds: 120),
      ]),
    ]);
    await openPane(tester, 'Alpha');
    final format = DateFormat('yyyy-MM-dd HH:mm');
    final newerText = find.textContaining(format.format(newer.toLocal()));
    final olderText = find.textContaining(format.format(older.toLocal()));
    expect(newerText, findsOneWidget);
    expect(olderText, findsOneWidget);
    expect(tester.getTopLeft(newerText).dy,
        lessThan(tester.getTopLeft(olderText).dy));
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
    final width = tester.getSize(find.byType(TextField)).width;
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
    await tester.enterText(find.byType(TextField), 'zzz');
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

  testWidgets('routes show completion and the active label',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', activeRoute: 'Rin', routes: [
        core.Route(name: 'Rin', completed: true),
        core.Route(name: 'Saber', completed: false),
      ]),
    ]);
    await openPane(tester, 'Alpha');
    expect(find.text('Rin'), findsOneWidget);
    expect(find.text('Saber'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('rating without a votecount shows no votes fallback',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', vndbRating: 85.0),
    ]);
    await openPane(tester, 'Alpha');
    expect(find.text('VNDB Rating'), findsOneWidget);
    expect(find.text('8.5'), findsOneWidget);
    expect(find.textContaining('votes'), findsNothing);
  });

  testWidgets('release shows the Released label', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', released: '2021-08-26'),
    ]);
    await openPane(tester, 'Alpha');
    expect(find.text('Released'), findsOneWidget);
    expect(find.text('2021-08-26'), findsOneWidget);
  });

  testWidgets('description heading follows the description',
      (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    expect(find.text('Description'), findsNothing);
    expect(find.text('Sessions'), findsNothing);
    expect(find.text('Routes'), findsNothing);
  });

  testWidgets('description and routes headings show with content',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(
        id: 'g1',
        title: 'Alpha',
        description: 'A story',
        routes: [core.Route(name: 'Rin')],
      ),
    ]);
    await openPane(tester, 'Alpha');
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Sessions'), findsNothing);
    expect(find.text('Routes'), findsOneWidget);
  });

  testWidgets('sessions heading shows only with sessions', (tester) async {
    await pumpLibrary(tester, [
      core.Game(
        id: 'g1',
        title: 'Alpha',
        playSessions: [
          core.PlaySession(
              startedAt: DateTime.utc(2024, 3, 4, 12, 30),
              durationSeconds: 120),
        ],
      ),
    ]);
    await openPane(tester, 'Alpha');
    expect(find.text('Sessions'), findsOneWidget);
  });

  testWidgets('rating, release and tags render beside the cover',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(
        id: 'g1',
        title: 'Alpha',
        released: '2024-05-06',
        vndbRating: 85.0,
        vndbVotecount: 12,
        tags: ['Action', 'Romance'],
      ),
    ]);
    await openPane(tester, 'Alpha');
    expect(find.text('VNDB Rating'), findsOneWidget);
    expect(find.text('8.5'), findsOneWidget);
    expect(find.text('12 votes'), findsOneWidget);
    expect(find.text('Released'), findsOneWidget);
    expect(find.text('2024-05-06'), findsOneWidget);
    expect(find.text('Action'), findsOneWidget);
    expect(find.text('Romance'), findsOneWidget);
    expect(find.text('Total playtime'), findsOneWidget);
    expect(find.text('0 min'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^Total \d')), findsNothing);
  });

  testWidgets('rating value divides by ten', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', vndbRating: 64),
    ]);
    await openPane(tester, 'Alpha');
    expect(find.text('6.4'), findsOneWidget);
  });

  testWidgets('facts sit beside the cover', (tester) async {
    setSurface(tester, 1280, 800);
    final temp = Directory.systemTemp.createTempSync('vnl_hero_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider
            .overrideWithValue(await SharedPreferences.getInstance()),
        dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
        libraryRepositoryProvider.overrideWithValue(DetailFakeRepository([
          core.Game(
              id: 'g1', title: 'Alpha', cover: 'cover.png', vndbRating: 64),
        ])),
        // No files on disk, so the images fall back — but the 190-wide
        // hero cover box still lays out.
        coverExistsProvider.overrideWithValue((_) => true),
      ],
      child: const VnlApp(),
    ));
    await tester.pump();
    await tester.pump();
    await openPane(tester, 'Alpha');
    final coverRect =
        tester.getRect(find.byKey(const ValueKey('detail-cover')));
    expect(coverRect.width, moreOrLessEquals(190, epsilon: 0.5));
    final labelTopLeft = tester.getTopLeft(find.text('VNDB Rating'));
    expect(labelTopLeft.dx, greaterThan(coverRect.right));
    expect((labelTopLeft.dy - coverRect.top).abs(), lessThanOrEqualTo(20));
    expect(find.text('6.4'), findsOneWidget);
  });
}
