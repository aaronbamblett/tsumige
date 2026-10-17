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

  Future<void> pumpBar(WidgetTester tester, AppTheme appTheme) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(
          theme: appTheme,
          brightness: Brightness.dark,
          customSeed: Colors.blue,
        ),
        home: const Scaffold(body: DesktopTitleBar()),
      ),
    );
  }

  testWidgets('title bar shows the Tsumige mark before the name', (
    tester,
  ) async {
    await pumpBar(tester, AppTheme.royal);

    final icon = tester.widget<ImageIcon>(find.byType(ImageIcon));
    expect(
      (icon.image as AssetImage).assetName,
      'assets/icon/tsumige_mark.png',
    );
    expect(icon.size, 16);
  });

  for (final appTheme in [AppTheme.royal, AppTheme.plum]) {
    testWidgets(
      'title bar mark is tinted with primary under ${appTheme.name}',
      (tester) async {
        await pumpBar(tester, appTheme);

        final scheme = buildAppTheme(
          theme: appTheme,
          brightness: Brightness.dark,
          customSeed: Colors.blue,
        ).colorScheme;
        final icon = tester.widget<ImageIcon>(find.byType(ImageIcon));
        expect(icon.color, scheme.primary);
      },
    );
  }
}
