// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vnl/src/features/settings/presentation/appearance/widgets/is_true_black/is_true_black_tile.dart';
import 'package:vnl/src/l10n/generated/app_localizations.dart';
import 'package:vnl/src/utils/prefs/prefs_mixin.dart';

void main() {
  testWidgets('the pure black leading has an onSurface ring',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider
            .overrideWithValue(await SharedPreferences.getInstance()),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: IsTrueBlackTile()),
      ),
    ));
    await tester.pump();
    await tester.pump();
    final circle = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
    );
    expect(circle, findsOneWidget);
    final decoration =
        tester.widget<Container>(circle).decoration! as BoxDecoration;
    expect(decoration.color, Colors.black);
    final border = decoration.border! as Border;
    final onSurface = Theme.of(
      tester.element(find.byType(IsTrueBlackTile)),
    ).colorScheme.onSurface;
    for (final side in [border.top, border.left, border.right, border.bottom]) {
      expect(side.color, onSurface);
      expect(side.width, 1.5);
    }
  });
}
