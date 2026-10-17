// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:vnl/src/core/launch/env.dart';

void main() {
  test('empty text gives no variables', () {
    expect(parseEnv(''), isEmpty);
  });

  test('comments and blank lines are skipped', () {
    expect(
      parseEnv('# leading comment\n\n  KEY=value  \n\t# indented\nOTHER=1\n'),
      {'KEY': 'value', 'OTHER': '1'},
    );
  });

  test('the first equals splits and both sides are trimmed', () {
    expect(parseEnv('KEY = a=b=c'), {'KEY': 'a=b=c'});
  });

  test('a line without equals is an error', () {
    expect(
      () => parseEnv('KEY=value\nBROKEN\nOTHER=1'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message',
          'Line 2 must be KEY=value')),
    );
  });

  test('an empty variable name is an error', () {
    expect(
      () => parseEnv('KEY=value\n=empty'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message',
          'Line 2 has an empty variable name')),
    );
  });

  test('whitespace in the variable name is an error', () {
    expect(
      () => parseEnv('MY KEY=value'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message',
          'Line 1 has whitespace in the variable name')),
    );
  });
}
