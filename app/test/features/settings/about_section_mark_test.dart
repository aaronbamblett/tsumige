// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumige/src/constants/app_theme.dart';
import 'package:tsumige/src/features/settings/presentation/sections/about_section.dart';
import 'package:tsumige/src/utils/theme/app_theme_builder.dart';

void main() {
  Future<void> pumpAbout(WidgetTester tester, AppTheme appTheme) {
    return tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(
            theme: appTheme,
            brightness: Brightness.dark,
            customSeed: Colors.blue,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(child: AboutSection()),
          ),
        ),
      ),
    );
  }

  testWidgets('About shows the Tsumige mark beside the heading', (
    tester,
  ) async {
    await pumpAbout(tester, AppTheme.royal);

    final icon = tester.widget<ImageIcon>(find.byType(ImageIcon));
    expect(
      (icon.image as AssetImage).assetName,
      'assets/icon/tsumige_mark.png',
    );
    expect(icon.size, 40);
  });

  for (final appTheme in [AppTheme.royal, AppTheme.plum]) {
    testWidgets('About mark is tinted with primary under ${appTheme.name}', (
      tester,
    ) async {
      await pumpAbout(tester, appTheme);

      final scheme = buildAppTheme(
        theme: appTheme,
        brightness: Brightness.dark,
        customSeed: Colors.blue,
      ).colorScheme;
      final icon = tester.widget<ImageIcon>(find.byType(ImageIcon));
      expect(icon.color, scheme.primary);
    });
  }
}
