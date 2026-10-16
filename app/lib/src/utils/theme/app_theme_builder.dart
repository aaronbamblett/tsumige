// Copyright (c) 2026 Contributors to the Suwayomi project
// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_theme.dart';
import 'app_color_scheme.dart';
import 'brand.dart';
import 'theme_tokens.dart';

/// Single source of truth for app ThemeData. The scheme is built explicitly
/// from the theme's own tokens; Material derives nothing.
ThemeData buildAppTheme({
  required AppTheme theme,
  required Brightness brightness,
}) {
  final tokens = tokensFor(theme, brightness);
  final scheme = schemeFromTokens(tokens, brightness);

  final brandColors = BrandColors(success: brandSuccessColor(brightness));

  final primary = scheme.primary;
  final outline = scheme.outlineVariant;
  // A lighter, more vibrant blue for text/outline actions (links…).
  final brightPrimary = brandBrightAccent(scheme);

  ButtonStyle filledLike() => ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(primary),
        foregroundColor: WidgetStatePropertyAll(scheme.onPrimary),
        shadowColor: WidgetStatePropertyAll(primary.withValues(alpha: 0.6)),
        elevation: const WidgetStatePropertyAll(6),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: [brandColors],
    scaffoldBackgroundColor: scheme.surface,
    // Left-aligned titles app-wide; flat surface app bar (no grey elevation).
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      // Make the status-bar icons track the theme brightness.
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: brightness == Brightness.dark
            ? Brightness.dark
            : Brightness.light,
        systemNavigationBarColor: scheme.surface,
        systemNavigationBarIconBrightness: brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    ),
    tabBarTheme: const TabBarThemeData(tabAlignment: TabAlignment.center),
    // Bottom navigation: accent-tinted selected indicator + accent selection.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      elevation: 0,
      indicatorColor: primary.withValues(alpha: 0.22),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? primary
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: s.contains(WidgetState.selected)
              ? primary
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: primary.withValues(alpha: 0.22),
      selectedIconTheme: IconThemeData(color: primary),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: TextStyle(
        color: primary,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    // Accent the leading icons of list rows (More/Settings etc.).
    listTileTheme: ListTileThemeData(
      iconColor: primary,
      selectedColor: primary,
      selectedTileColor: primary.withValues(alpha: 0.16),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: outline),
      ),
    ),
    dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: tokens.accentBg,
      side: WidgetStateBorderSide.resolveWith(
        (s) => BorderSide(
          color: s.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.outlineVariant,
        ),
      ),
      labelStyle: TextStyle(color: scheme.onSurface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? primary : scheme.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? primary.withValues(alpha: 0.45)
            : scheme.surfaceContainerHighest,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: primary,
      inactiveTrackColor: primary.withValues(alpha: 0.22),
      thumbColor: primary,
      overlayColor: primary.withValues(alpha: 0.18),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: scheme.onPrimary,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(style: filledLike()),
    elevatedButtonTheme: ElevatedButtonThemeData(style: filledLike()),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(brightPrimary),
        side: WidgetStatePropertyAll(
          BorderSide(color: primary.withValues(alpha: 0.5)),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(brightPrimary),
      ),
    ),
  );
}
