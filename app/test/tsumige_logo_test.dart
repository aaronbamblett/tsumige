// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:tsumige/src/constants/app_theme.dart';
import 'package:tsumige/src/features/settings/presentation/appearance/widgets/app_theme_selector/app_theme_providers.dart';
import 'package:tsumige/src/utils/prefs/prefs_mixin.dart';
import 'package:tsumige/src/utils/theme/app_theme_builder.dart';
import 'package:tsumige/src/widgets/tsumige_logo.dart';

const _markAsset = 'assets/icon/tsumige_mark.png';
const _onLightAsset = 'assets/icon/tsumige_mark_on_light.png';
const _shadowAsset = 'assets/icon/tsumige_mark_shadow.png';
const _foregroundAsset = 'assets/icon/tsumige_mark_foreground.png';
const _onLightShadowAsset = 'assets/icon/tsumige_mark_on_light_shadow.png';
const _onLightForegroundAsset =
    'assets/icon/tsumige_mark_on_light_foreground.png';

bool _isAsset(Widget widget, String path) =>
    widget is Image &&
    widget.image is AssetImage &&
    (widget.image as AssetImage).assetName == path;

Finder _image(String path) => find.byWidgetPredicate((w) => _isAsset(w, path));

class _Theme extends AppThemeKey {
  _Theme(this.value);

  final AppTheme value;

  @override
  AppTheme? build() => value;
}

ThemeData _theme(AppTheme theme, Brightness brightness) => buildAppTheme(
  theme: theme,
  brightness: brightness,
  customSeed: Colors.blue,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required AppTheme theme,
  required Brightness brightness,
  bool disableAnimations = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        appThemeKeyProvider.overrideWith(() => _Theme(theme)),
      ],
      child: MaterialApp(
        theme: _theme(theme, brightness),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: disableAnimations),
            child: Scaffold(body: Center(child: child)),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('Royal dark draws the original mark only', (tester) async {
    await _pump(
      tester,
      const TsumigeLogo(size: 48),
      theme: AppTheme.royal,
      brightness: Brightness.dark,
    );

    expect(_image(_markAsset), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
    expect(_image(_shadowAsset), findsNothing);
    expect(_image(_foregroundAsset), findsNothing);
  });

  testWidgets('Royal light draws the on-light mark', (tester) async {
    await _pump(
      tester,
      const TsumigeLogo(size: 48),
      theme: AppTheme.royal,
      brightness: Brightness.light,
    );

    expect(_image(_onLightAsset), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
    expect(_image(_onLightShadowAsset), findsNothing);
  });

  for (final theme in [AppTheme.indigoNight, AppTheme.carbon]) {
    testWidgets(
      '${theme.name} dark tints the shadow and keeps the foreground',
      (tester) async {
        await _pump(
          tester,
          const TsumigeLogo(size: 48),
          theme: theme,
          brightness: Brightness.dark,
        );

        expect(find.byType(ShaderMask), findsOneWidget);
        expect(_image(_shadowAsset), findsOneWidget);
        expect(_image(_foregroundAsset), findsOneWidget);
        expect(_image(_markAsset), findsNothing);
      },
    );

    test('${theme.name} dark gradient runs from the lighter accent down', () {
      final scheme = schemeFor(theme, Brightness.dark, Colors.blue);
      final (top, bottom) = tsumigeShadowColors(scheme);

      expect({top, bottom}, {scheme.primary, scheme.secondary});
      expect(
        top.computeLuminance(),
        greaterThanOrEqualTo(bottom.computeLuminance()),
      );
    });
  }

  for (final theme in [AppTheme.catppuccin, AppTheme.ember]) {
    testWidgets('${theme.name} light tints the on-light shadow', (
      tester,
    ) async {
      await _pump(
        tester,
        const TsumigeLogo(size: 48),
        theme: theme,
        brightness: Brightness.light,
      );

      expect(find.byType(ShaderMask), findsOneWidget);
      expect(_image(_onLightShadowAsset), findsOneWidget);
      expect(_image(_onLightForegroundAsset), findsOneWidget);
      expect(_image(_onLightAsset), findsNothing);
      expect(_image(_shadowAsset), findsNothing);
    });

    test('${theme.name} light gradient uses the dark palette accents', () {
      final dark = schemeFor(theme, Brightness.dark, Colors.blue);
      final light = schemeFor(theme, Brightness.light, Colors.blue);
      final (top, bottom) = tsumigeShadowColors(dark);

      expect({top, bottom}, {dark.primary, dark.secondary});
      expect({top, bottom}, isNot({light.primary, light.secondary}));
      expect(
        top.computeLuminance(),
        greaterThanOrEqualTo(bottom.computeLuminance()),
      );
    });
  }

  test('Catppuccin dark accents match theme-kit', () {
    final dark = schemeFor(AppTheme.catppuccin, Brightness.dark, Colors.blue);
    expect(tsumigeShadowColors(dark), (
      const Color(0xFFCBA6F7),
      const Color(0xFF89B4FA),
    ));
  });

  testWidgets('a logo is size x size under loose constraints', (tester) async {
    await _pump(
      tester,
      const TsumigeLogo(size: 48),
      theme: AppTheme.carbon,
      brightness: Brightness.dark,
    );

    expect(tester.getSize(find.byType(TsumigeLogo)), const Size(48, 48));
  });

  testWidgets('the shimmer animates when motion is allowed', (tester) async {
    await _pump(
      tester,
      const TsumigeLogoShimmer(size: 48),
      theme: AppTheme.royal,
      brightness: Brightness.dark,
    );

    expect(find.byType(Shimmer), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(Shimmer), findsOneWidget);
    expect(tester.getSize(find.byType(ImageIcon)), const Size(48, 48));
  });

  testWidgets('the shimmer is a static primary silhouette when reduced', (
    tester,
  ) async {
    await _pump(
      tester,
      const TsumigeLogoShimmer(size: 48),
      theme: AppTheme.royal,
      brightness: Brightness.dark,
      disableAnimations: true,
    );

    expect(find.byType(Shimmer), findsNothing);
    final icon = tester.widget<ImageIcon>(find.byType(ImageIcon));
    expect((icon.image as AssetImage).assetName, _markAsset);
    expect(
      icon.color,
      _theme(AppTheme.royal, Brightness.dark).colorScheme.primary,
    );
    expect(icon.size, 48);
  });
}
