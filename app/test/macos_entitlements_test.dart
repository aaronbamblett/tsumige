// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final readOnly = RegExp(
    r'<key>com\.apple\.security\.files\.user-selected\.read-only</key>\s*<true/>',
  );
  for (final name in ['Release.entitlements', 'DebugProfile.entitlements']) {
    test('$name grants user-selected read-only so macOS pickers open', () {
      final text = File('macos/Runner/$name').readAsStringSync();
      expect(readOnly.hasMatch(text), isTrue);
    });
  }
}
