// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumige/src/core/launch/steam_registry.dart';

void main() {
  test('a hex RunningAppID is read as its decimal app id', () {
    const output = '\r\nHKEY_CURRENT_USER\\Software\\Valve\\Steam\r\n'
        '    RunningAppID    REG_DWORD    0x3e8\r\n\r\n';
    expect(parseRunningAppId(output), 1000);
  });

  test('a RunningAppID of 0 means no game is running', () {
    expect(
      parseRunningAppId('    RunningAppID    REG_DWORD    0x0\r\n'),
      isNull,
    );
  });

  test('output without the value means no game is running', () {
    expect(parseRunningAppId('ERROR: The system was unable to find it.'),
        isNull);
    expect(parseRunningAppId(''), isNull);
  });

  test('a decimal value is read too', () {
    expect(parseRunningAppId('    RunningAppID    REG_DWORD    42\n'), 42);
  });
}
