// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumige/src/features/library/presentation/widgets/group_name_dialog.dart';

void main() {
  test('a shared part-marker prefix names the series', () {
    expect(
      combineDefaultName([
        '9-nine- Episode 1',
        '9-nine- Episode 2',
        '9-nine- Episode 3',
      ]),
      '9-nine-',
    );
  });

  test('a spaced separator after the series name is trimmed', () {
    expect(
      combineDefaultName([
        'Higurashi When They Cry Hou - Ch.1 Onikakushi',
        'Higurashi When They Cry Hou - Ch.2 Watanagashi',
      ]),
      'Higurashi When They Cry Hou',
    );
  });

  test('titles without a shared marker fall back to the shared prefix', () {
    expect(combineDefaultName(['Solo A', 'Solo B']), 'Solo');
  });

  test('a title without a marker falls back to the first title', () {
    expect(
      combineDefaultName(['Duo Episode 1', 'Duo Episode 2', 'Lone Wolf']),
      'Duo Episode 1',
    );
  });
}
