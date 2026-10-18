// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumige/src/constants/app_theme.dart';
import 'package:tsumige/src/utils/theme/app_theme_builder.dart';
import 'package:tsumige/src/widgets/desktop/desktop_title_bar.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => false,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });

  Future<void> pumpBar(
    WidgetTester tester,
    AppTheme appTheme,
    Brightness brightness,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(
          theme: appTheme,
          brightness: brightness,
          customSeed: Colors.blue,
        ),
        home: const Scaffold(body: DesktopTitleBar()),
      ),
    );
  }

  for (final appTheme in [AppTheme.royal, AppTheme.plum]) {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      final asset = brightness == Brightness.dark
          ? 'assets/icon/tsumige_mark.png'
          : 'assets/icon/tsumige_mark_on_light.png';
      testWidgets(
        'title bar shows the $asset mark in full colour under ${appTheme.name} ${brightness.name}',
        (tester) async {
          await pumpBar(tester, appTheme, brightness);

          expect(find.byType(ImageIcon), findsNothing);
          final image = tester.widget<Image>(find.byType(Image));
          expect((image.image as AssetImage).assetName, asset);
          expect(image.height, 18);
          expect(image.color, isNull);
        },
      );
    }
  }
}
