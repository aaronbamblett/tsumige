// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vnl/src/utils/desktop/desktop_window.dart';

void main() {
  test('minimum window size is 1000 by 640', () async {
    Size? applied;
    await setMinimumWindowSize(setter: (size) async => applied = size);
    expect(applied, const Size(1000, 640));
    expect(kMinWindowSize, const Size(1000, 640));
  });
}
