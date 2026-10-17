// Copyright (c) 2026 Contributors to the Suwayomi project
// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

/// Helper class for device related operations.
///
extension ContextExtensions on BuildContext {
  /// The same of [MediaQuery.of(context).size.height]
  /// Note: updates when you resize your screen (like on a browser or
  /// desktop window)
  double get height => MediaQuery.of(this).size.height;

  /// similar to [MediaQuery.of(context).padding]
  ThemeData get theme => Theme.of(this);

  /// Check if dark mode theme is enable
  bool get isDarkMode => (theme.brightness == Brightness.dark);
}
