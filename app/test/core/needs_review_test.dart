// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumige/src/core/model.dart';

void main() {
  test('needsReview defaults to false and round-trips through JSON', () {
    final plain = Game(id: 'g1', title: 'Plain');
    expect(plain.needsReview, isFalse);
    expect(plain.toJson()['needs_review'], isFalse);
    expect(Game.fromJson({'id': 'g1'}).needsReview, isFalse);

    final flagged = Game(id: 'g2', title: 'Flagged', needsReview: true);
    final back = Game.fromJson(flagged.toJson());
    expect(back.needsReview, isTrue);
  });
}
