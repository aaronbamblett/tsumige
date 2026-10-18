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
  Future<void> pumpAbout(
    WidgetTester tester,
    AppTheme appTheme,
    Brightness brightness,
  ) {
    return tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(
            theme: appTheme,
            brightness: brightness,
            customSeed: Colors.blue,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(child: AboutSection()),
          ),
        ),
      ),
    );
  }

  for (final appTheme in [AppTheme.royal, AppTheme.plum]) {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      final asset = brightness == Brightness.dark
          ? 'assets/icon/tsumige_mark.png'
          : 'assets/icon/tsumige_mark_on_light.png';
      testWidgets(
        'About shows the $asset mark in full colour under ${appTheme.name} ${brightness.name}',
        (tester) async {
          await pumpAbout(tester, appTheme, brightness);

          expect(find.byType(ImageIcon), findsNothing);
          final image = tester.widget<Image>(find.byType(Image));
          expect((image.image as AssetImage).assetName, asset);
          expect(image.height, 48);
          expect(image.color, isNull);
        },
      );
    }
  }
}
