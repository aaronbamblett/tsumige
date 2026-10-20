// Copyright (c) 2026 Contributors to the Suwayomi project
// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../platform/platform_runtime.dart';
import 'window_geometry.dart';
import 'window_geometry_listener.dart';
import 'window_geometry_store.dart';

// Narrower than this and the toolbar's controls run into each other.
// Kept in sync with the GtkWindow geometry hint in my_application.cc,
// which is what enforces it on Linux.
const kMinWindowSize = Size(1000, 640);
const kDefaultWindowSize = Size(1280, 900);

typedef MinimumSizeSetter = Future<void> Function(Size size);

/// Applies [kMinWindowSize] through [setter], which defaults to window_manager.
Future<void> setMinimumWindowSize({MinimumSizeSetter? setter}) =>
    (setter ?? windowManager.setMinimumSize)(kMinWindowSize);

/// Initialise the desktop window: hide the OS title bar, restore the
/// saved size/maximized state, and show only once Flutter is ready (no white
/// flash). Position is never saved or restored. No-op on web/mobile.
Future<void> initDesktopWindow(SharedPreferences prefs) async {
  if (!isDesktopPlatform) return;

  await windowManager.ensureInitialized();

  final saved = loadWindowGeometry(prefs);
  final restoreSize = resolveRestoreSize(
    saved,
    fallback: kDefaultWindowSize,
    min: kMinWindowSize,
  );

  final options = WindowOptions(
    size: restoreSize,
    minimumSize: kMinWindowSize,
    center: saved.size == null,
    titleBarStyle: TitleBarStyle.hidden,
    // macOS: keep the native traffic lights floating over our surface.
    windowButtonVisibility: Platform.isMacOS,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await setMinimumWindowSize();
    if (saved.maximized) {
      await windowManager.maximize();
    } else {
      await windowManager.setSize(restoreSize);
    }
    await windowManager.setPreventClose(true);
    attachWindowGeometryListener(prefs);
    // Show after Flutter's first frame, not here — the rest of startup still
    // runs before runApp, and showing early flashes a blank window.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await windowManager.show();
      await windowManager.focus();
    });
  });
}
