// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../constants/app_theme.dart';

/// Color tokens for the app theme at one brightness.
///
/// Every role is set from these hexes; Material derives nothing.
class ThemeTokens {
  const ThemeTokens({
    required this.bg,
    required this.bg2,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.accent2,
    required this.danger,
    required this.border,
    this.onAccent,
    this.accentBg,
  });

  final Color bg;
  final Color bg2;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color accent;
  final Color accent2;
  final Color danger;
  final Color border;

  final Color? onAccent;
  final Color? accentBg;
}

/// The single seed colour the neutral scheme is built around.
const vnlSeedColor = Color(0xFF5B8DEF);

const _vnlDark = ThemeTokens(
  bg: Color(0xFF121417),
  bg2: Color(0xFF1A1D21),
  ink: Color(0xFFE8EAED),
  muted: Color(0xFF9AA0A6),
  faint: Color(0xFF5F6368),
  accent: Color(0xFF9DBEFF),
  accent2: Color(0xFF80CBC4),
  danger: Color(0xFFF28B82),
  border: Color(0x14FFFFFF),
  onAccent: Color(0xFF0A1B33),
  accentBg: Color(0xFF233148),
);

const _vnlLight = ThemeTokens(
  bg: Color(0xFFF1F3F4),
  bg2: Color(0xFFFFFFFF),
  ink: Color(0xFF202124),
  muted: Color(0xFF5F6368),
  faint: Color(0xFF80868B),
  accent: Color(0xFF2F6BDE),
  accent2: Color(0xFF00796B),
  danger: Color(0xFFB3261E),
  border: Color(0xFFDADCE0),
  onAccent: Color(0xFFFFFFFF),
  accentBg: Color(0xFFD9E4FF),
);

ThemeTokens tokensFor(AppTheme theme, Brightness brightness) {
  assert(theme == AppTheme.vnl, 'only the vnl theme has fixed tokens');
  return brightness == Brightness.dark ? _vnlDark : _vnlLight;
}
