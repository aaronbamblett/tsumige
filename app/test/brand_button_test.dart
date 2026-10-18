// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumige/src/constants/app_theme.dart';
import 'package:tsumige/src/utils/theme/app_theme_builder.dart';
import 'package:tsumige/src/utils/theme/brand.dart';

ThemeData _theme() => buildAppTheme(
  theme: AppTheme.royal,
  brightness: Brightness.dark,
  customSeed: Colors.blue,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: _theme(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pump();
}

BoxDecoration _decoration(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
  return box.decoration as BoxDecoration;
}

Color _labelColor(WidgetTester tester, String text) {
  final element = tester.element(find.text(text));
  return DefaultTextStyle.of(element).style.color!;
}

void main() {
  testWidgets('enabled BrandButton has the brand gradient and the glow', (
    tester,
  ) async {
    await _pump(
      tester,
      BrandButton(onPressed: () {}, label: const Text('Add Games')),
    );
    final decoration = _decoration(tester);
    final cs = _theme().colorScheme;
    expect(
      decoration.gradient,
      BrandColors.of(tester.element(find.text('Add Games'))).gradient,
    );
    expect(decoration.boxShadow, brandGlow(cs));
  });

  testWidgets('disabled BrandButton is greyed out', (tester) async {
    await _pump(
      tester,
      const BrandButton(onPressed: null, label: Text('Add Games')),
    );
    final decoration = _decoration(tester);
    final cs = _theme().colorScheme;
    expect(decoration.gradient, isNull);
    expect(decoration.boxShadow, isNull);
    expect(decoration.color, cs.onSurface.withValues(alpha: 0.12));
    expect(
      _labelColor(tester, 'Add Games'),
      cs.onSurface.withValues(alpha: 0.38),
    );
  });

  testWidgets('loading BrandButton keeps the gradient', (tester) async {
    await _pump(
      tester,
      const BrandButton(
        onPressed: null,
        loading: true,
        label: Text('Add Games'),
      ),
    );
    final decoration = _decoration(tester);
    expect(decoration.gradient, isNotNull);
  });

  testWidgets('disabled BrandGlassButton greys the label', (tester) async {
    await _pump(
      tester,
      const BrandGlassButton(onPressed: null, label: Text('Select')),
    );
    expect(
      _labelColor(tester, 'Select'),
      _theme().colorScheme.onSurface.withValues(alpha: 0.38),
    );
  });

  testWidgets('enabled BrandGlassButton uses the bright accent', (
    tester,
  ) async {
    await _pump(
      tester,
      BrandGlassButton(onPressed: () {}, label: const Text('Select')),
    );
    expect(
      _labelColor(tester, 'Select'),
      brandBrightAccent(_theme().colorScheme),
    );
  });
}
