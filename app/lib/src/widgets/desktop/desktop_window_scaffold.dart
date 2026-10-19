// Copyright (c) 2026 Contributors to the Suwayomi project
// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../routes/router.dart';
import '../../utils/platform/platform_runtime.dart';
import 'desktop_title_bar.dart';

/// Wraps the app with the custom title bar on desktop. A Column, not an
/// overlay Stack — the opaque bar must push content down, never occlude it
/// (macOS traffic lights float over the bar's left edge). The bar is hidden
/// on the library route, which draws its own top bar instead; every other
/// route keeps the plain title bar.
class DesktopWindowScaffold extends ConsumerWidget {
  const DesktopWindowScaffold({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isDesktopPlatform) return child;

    final showTitleBar = ref.watch(scaffoldTitleBarProvider);
    return Column(
      children: [
        if (showTitleBar) const DesktopTitleBar(),
        Expanded(child: child),
      ],
    );
  }
}
