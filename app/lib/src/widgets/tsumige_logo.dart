// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../constants/app_theme.dart';
import '../features/settings/presentation/appearance/widgets/app_theme_selector/app_theme_providers.dart';
import '../utils/theme/app_theme_builder.dart';

const _markAsset = 'assets/icon/tsumige_mark.png';
const _onLightAsset = 'assets/icon/tsumige_mark_on_light.png';
const _shadowAsset = 'assets/icon/tsumige_mark_shadow.png';
const _foregroundAsset = 'assets/icon/tsumige_mark_foreground.png';
const _onLightShadowAsset = 'assets/icon/tsumige_mark_on_light_shadow.png';
const _onLightForegroundAsset =
    'assets/icon/tsumige_mark_on_light_foreground.png';

/// The shadow gradient's (top, bottom) colours: the lighter accent on top.
(Color, Color) tsumigeShadowColors(ColorScheme scheme) =>
    scheme.primary.computeLuminance() > scheme.secondary.computeLuminance()
    ? (scheme.primary, scheme.secondary)
    : (scheme.secondary, scheme.primary);

/// The full-colour Tsumige mark. The home theme (Royal) keeps its artwork in
/// both modes. Any other theme tints the brush shadow with its dark palette's
/// accents and draws the foreground untinted; light themes use the on-light art.
class TsumigeLogo extends ConsumerWidget {
  const TsumigeLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final light = scheme.brightness == Brightness.light;
    final theme = ref.watch(appThemeKeyProvider) ?? kDefaultAppTheme;
    if (theme == AppTheme.royal) {
      return Image.asset(
        light ? _onLightAsset : _markAsset,
        width: size,
        height: size,
      );
    }
    final seed = Color(ref.watch(customThemeColorProvider) ?? 0xFF7C7BFF);
    final tint = light ? schemeFor(theme, Brightness.dark, seed) : scheme;
    final (top, bottom) = tsumigeShadowColors(tint);
    return Stack(
      alignment: Alignment.center,
      children: [
        ShaderMask(
          blendMode: BlendMode.modulate,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, bottom],
          ).createShader(bounds),
          child: Image.asset(
            light ? _onLightShadowAsset : _shadowAsset,
            width: size,
            height: size,
          ),
        ),
        Image.asset(
          light ? _onLightForegroundAsset : _foregroundAsset,
          width: size,
          height: size,
        ),
      ],
    );
  }
}

/// The loading state: the flat mark silhouette, shimmering from the surface to
/// the primary colour. Under reduced motion it is a static primary silhouette.
class TsumigeLogoShimmer extends StatelessWidget {
  const TsumigeLogoShimmer({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = AssetImage(_markAsset);
    if (MediaQuery.of(context).disableAnimations) {
      return ImageIcon(icon, size: size, color: scheme.primary);
    }
    return Shimmer.fromColors(
      baseColor: scheme.surface,
      highlightColor: scheme.primary,
      child: ImageIcon(icon, size: size),
    );
  }
}
