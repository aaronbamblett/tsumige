// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:test/test.dart';
import 'package:vnl_core/vnl_core.dart';

void main() {
  test('formatPlaytime', () {
    expect(formatPlaytime(0), '0 min');
    expect(formatPlaytime(3599), '59 min');
    expect(formatPlaytime(3600), '1.0 hrs');
    expect(formatPlaytime(5400), '1.5 hrs');
  });

  test('formatVndbRating', () {
    expect(formatVndbRating(84.23), 'VNDB Rating 8.4');
  });
}
