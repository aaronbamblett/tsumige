// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumige/src/constants/app_theme.dart';
import 'package:tsumige/src/utils/font_licenses.dart';
import 'package:tsumige/src/utils/theme/app_theme_builder.dart';

ThemeData themeFor(Brightness brightness) => buildAppTheme(
      theme: kDefaultAppTheme,
      brightness: brightness,
      customSeed: const Color(0xFF7C7BFF),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('light and dark app themes resolve text in Inter', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final theme = themeFor(brightness);
      expect(theme.textTheme.bodyLarge?.fontFamily, 'Inter');
    }
  });

  test('Inter Bold (700) asset is declared', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('assets/fonts/Inter-Bold.ttf'));
    expect(pubspec, contains('weight: 700'));
    expect(File('assets/fonts/Inter-Bold.ttf').existsSync(), isTrue);
  });

  test('Inter licence is registered', () async {
    registerFontLicenses();
    var found = false;
    await for (final entry in LicenseRegistry.licenses) {
      if (entry.packages.contains('Inter')) {
        found = true;
        break;
      }
    }
    expect(found, isTrue);
  });
}
