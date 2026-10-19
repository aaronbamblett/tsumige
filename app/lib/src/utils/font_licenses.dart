// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// lib/src/utils/font_licenses.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Registers the bundled Inter licence (SIL OFL 1.1) with Flutter's
/// [LicenseRegistry], so it shows under package `Inter` on the licences page.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/Inter-OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Inter'], text);
  });
}
