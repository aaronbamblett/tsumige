// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

/// App-level themes. Only the neutral vn-launcher theme exists; the enum is
/// what `app_theme_builder.dart` imports, mirroring Tsumiru's shape.
enum AppTheme {
  vnl;

  /// (accent, accent2) used for a swatch preview.
  (Color, Color) get swatch => (
        const Color(0xFF2F6BDE),
        const Color(0xFF00796B),
      );
}
