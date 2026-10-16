// Copyright (c) 2026 Contributors to the Suwayomi project
// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import 'theme_tokens.dart';

/// Builds a complete Material 3 [ColorScheme] EXPLICITLY from brand
/// [ThemeTokens]. Every role is set from the theme's own hexes — there is NO
/// `ColorScheme.fromSeed` and Material derives no colors. Elevated surfaces are
/// the theme's `bg2` (the theme maps every elevated surface to bg2); the few M3
/// container roles the theme doesn't name are simple lerps of the theme's own
/// accent over its background (deterministic, never Material's tonal palette).
ColorScheme schemeFromTokens(ThemeTokens t, Brightness brightness) {
  Color mix(Color a, Color b, double amt) => Color.lerp(a, b, amt)!;

  final accentBg = t.accentBg;

  return ColorScheme(
    brightness: brightness,
    // Brand accents (verbatim)
    primary: t.accent,
    // Contrast against the accent, not always white: a light accent needs dark
    // text so primary-filled elements stay legible.
    onPrimary: accentBg != null
        ? t.onAccent!
        : ThemeData.estimateBrightnessForColor(t.accent) == Brightness.light
            ? Colors.black
            : Colors.white,
    primaryContainer: accentBg ?? mix(t.accent, t.bg, 0.72),
    onPrimaryContainer: t.accent,
    secondary: t.accent2,
    onSecondary: accentBg != null ? t.onAccent! : t.bg,
    secondaryContainer: accentBg ?? mix(t.accent2, t.bg, 0.72),
    onSecondaryContainer: accentBg != null ? t.accent : t.accent2,
    tertiary: t.accent2,
    onTertiary: accentBg != null ? t.onAccent! : t.bg,
    tertiaryContainer: mix(t.accent2, t.bg, 0.72),
    onTertiaryContainer: t.accent2,
    error: t.danger,
    onError: Colors.white,
    errorContainer: mix(t.danger, t.bg, 0.72),
    onErrorContainer: t.danger,
    // Surfaces (verbatim): base = bg, every elevated surface = bg2
    surface: t.bg,
    onSurface: t.ink,
    onSurfaceVariant: t.muted,
    surfaceDim: t.bg,
    surfaceBright: t.bg2,
    surfaceContainerLowest: t.bg,
    surfaceContainerLow: t.bg2,
    surfaceContainer: t.bg2,
    surfaceContainerHigh: t.bg2,
    surfaceContainerHighest: t.bg2,
    // Lines
    outline: t.faint,
    outlineVariant: t.border,
    // Misc roles (from the theme's own colors)
    inverseSurface: t.ink,
    onInverseSurface: t.bg,
    inversePrimary: t.accent,
    scrim: Colors.black,
    shadow: Colors.black,
    // No elevation tinting — keep surfaces exactly as specified above.
    surfaceTint: Colors.transparent,
  );
}
