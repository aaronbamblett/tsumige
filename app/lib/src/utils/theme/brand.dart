// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

/// The active theme's extra brand roles, registered by [buildAppTheme].
class BrandColors extends ThemeExtension<BrandColors> {
  const BrandColors({required this.success});

  /// Positive-status colour (rating refresh finished).
  final Color success;

  @override
  BrandColors copyWith({Color? success}) =>
      BrandColors(success: success ?? this.success);

  @override
  BrandColors lerp(ThemeExtension<BrandColors>? other, double t) {
    if (other is! BrandColors) return this;
    return BrandColors(
      success: Color.lerp(success, other.success, t)!,
    );
  }

  static BrandColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<BrandColors>() ??
        BrandColors(
          success: brandSuccessColor(theme.colorScheme.brightness),
        );
  }
}

/// Positive-status colour. No [ColorScheme] role means "success", and
/// `Colors.green` is ~1.7:1 on a light surface, so each brightness gets a
/// green that clears 4.5:1 against its own surface.
Color brandSuccessColor(Brightness brightness) => brightness == Brightness.dark
    ? const Color(0xFF34E0A1)
    : const Color(0xFF00754A);

/// Star-rating colour. Amber is conventional and reads on dark surfaces; on a
/// light one it drops to ~1.8:1, so light takes a darker amber at 3:1.
Color brandStarColor(Brightness brightness) =>
    brightness == Brightness.dark ? Colors.amber : const Color(0xFFB7791F);

/// A lighter, more vibrant accent for text/outline actions (links).
/// Light mode keeps the deep primary; lightening it would undo its contrast.
Color brandBrightAccent(ColorScheme cs) => cs.brightness == Brightness.light
    ? cs.primary
    : Color.lerp(cs.primary, Colors.white, 0.22)!;
