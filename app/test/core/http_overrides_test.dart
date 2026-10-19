// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumige/src/core/http_overrides.dart';

void main() {
  test('caps connections per host', () {
    final client = HttpOverrides.runWithHttpOverrides(
      () => HttpClient(),
      TsumigeHttpOverrides(),
    );
    expect(client.maxConnectionsPerHost, 6);
    client.close();
  });
}
