// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

/// Reports the Steam app id Steam says is running. Windows only: Steam keeps
/// it in `HKCU\Software\Valve\Steam\RunningAppID`, and 0 or null means none.
abstract class SteamRegistry {
  Future<int?> runningAppId();
}

class RegSteamRegistry implements SteamRegistry {
  @override
  Future<int?> runningAppId() async {
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKCU\Software\Valve\Steam',
        '/v',
        'RunningAppID',
      ]);
      if (result.exitCode != 0) return null;
      return parseRunningAppId(result.stdout as String);
    } catch (_) {
      return null;
    }
  }
}

/// The app id in `reg query` output, or null when it is missing or 0.
int? parseRunningAppId(String output) {
  for (final line in output.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length != 3 || parts[0] != 'RunningAppID') continue;
    final raw = parts[2];
    final value = raw.startsWith('0x')
        ? int.tryParse(raw.substring(2), radix: 16)
        : int.tryParse(raw);
    return value == null || value == 0 ? null : value;
  }
  return null;
}
