// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:test/test.dart';
import 'package:vnl_core/vnl_core.dart';

void main() {
  test('vnlVersion is 0.1.0', () {
    expect(vnlVersion, equals('0.1.0'));
  });
}
