// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumige/src/core/format.dart';

void main() {
  test('formatPlaytime', () {
    expect(formatPlaytime(0), '<1 min');
    expect(formatPlaytime(19), '<1 min');
    expect(formatPlaytime(59), '<1 min');
    expect(formatPlaytime(60), '1 min');
    expect(formatPlaytime(3599), '59 min');
    expect(formatPlaytime(3600), '1.0 hrs');
    expect(formatPlaytime(5400), '1.5 hrs');
  });

  test('formatPlayDay names today and yesterday, else a short date', () {
    final now = DateTime(2026, 10, 17, 9, 30);
    expect(formatPlayDay(DateTime(2026, 10, 17, 0, 5), now), 'Today');
    expect(formatPlayDay(DateTime(2026, 10, 16, 23, 59), now), 'Yesterday');
    expect(formatPlayDay(DateTime(2026, 10, 12, 20), now), 'Oct 12');
    expect(formatPlayDay(DateTime(2025, 12, 31, 20), now), 'Dec 31, 2025');
  });

  test('formatVndbRating', () {
    expect(formatVndbRating(84.23), 'VNDB rating 8.4');
  });
}
