// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vnl/src/features/settings/presentation/appearance/widgets/app_theme_selector/app_theme_selector.dart';
import 'package:vnl/src/l10n/generated/app_localizations.dart';
import 'package:vnl/src/utils/prefs/prefs_mixin.dart';

Future<void> pumpSelector(WidgetTester tester, Size surface) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider
          .overrideWithValue(await SharedPreferences.getInstance()),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ThemeSelector(title: Text('Theme')),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

Finder leftArrow() => find.widgetWithIcon(IconButton, Icons.chevron_left_rounded);
Finder rightArrow() =>
    find.widgetWithIcon(IconButton, Icons.chevron_right_rounded);

double scrollOffset(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

void main() {
  testWidgets('at 1280 wide the arrows scroll the list forward',
      (tester) async {
    await pumpSelector(tester, const Size(1280, 800));
    expect(leftArrow(), findsOneWidget);
    expect(rightArrow(), findsOneWidget);
    expect(tester.widget<IconButton>(leftArrow()).onPressed, isNull);
    expect(tester.widget<IconButton>(rightArrow()).onPressed, isNotNull);
    expect(find.text('Theme'), findsOneWidget);
    final before = scrollOffset(tester);
    await tester.tap(rightArrow());
    await tester.pumpAndSettle();
    expect(scrollOffset(tester), greaterThan(before));
    expect(tester.widget<IconButton>(leftArrow()).onPressed, isNotNull);
  });

  testWidgets('reaching the end keeps the scroll position', (tester) async {
    await pumpSelector(tester, const Size(1280, 800));
    expect(find.byType(ShaderMask), findsOneWidget);
    final before =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    final max = before.maxScrollExtent;
    expect(max, greaterThan(0));
    before.jumpTo(max);
    await tester.pump();
    await tester.pump();
    final after =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(identical(after, before), isTrue);
    expect(after.pixels, max);
  });

  test('the fade stops apply only while there is more to scroll right', () {
    expect(
      ThemeSelector.edgeFadeStops(1248, true),
      [0, (1 - 40 / 1248).clamp(0, 1), 1],
    );
    expect(ThemeSelector.edgeFadeStops(1248, false), isNull);
  });

  testWidgets('no arrows when every card fits', (tester) async {
    await pumpSelector(tester, const Size(1800, 800));
    expect(leftArrow(), findsNothing);
    expect(rightArrow(), findsNothing);
    expect(find.text('Theme'), findsOneWidget);
  });
}
