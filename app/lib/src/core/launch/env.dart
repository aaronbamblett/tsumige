// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

Map<String, String> parseEnv(String text) {
  final env = <String, String>{};
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq < 0) {
      throw FormatException('Line ${i + 1} must be KEY=value');
    }
    final name = line.substring(0, eq).trim();
    final value = line.substring(eq + 1).trim();
    if (name.isEmpty) {
      throw FormatException('Line ${i + 1} has an empty variable name');
    }
    if (name.contains(RegExp(r'\s'))) {
      throw FormatException(
          'Line ${i + 1} has whitespace in the variable name');
    }
    env[name] = value;
  }
  return env;
}
