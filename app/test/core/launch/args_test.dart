// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:vnl/src/core/launch/args.dart';

void main() {
  test('empty input gives no args', () {
    expect(splitArgs(''), isEmpty);
    expect(splitArgs('   '), isEmpty);
  });

  test('whitespace runs separate arguments', () {
    expect(splitArgs('--fullscreen --windowed'), ['--fullscreen', '--windowed']);
    expect(splitArgs('  a\tb\nc  '), ['a', 'b', 'c']);
  });

  test('quoted args with spaces lose their quotes', () {
    expect(
      splitArgs(r'-a "C:\\Program Files\\x.exe" '"'"'two words'"'"' plain'),
      ['-a', r'C:\Program Files\x.exe', 'two words', 'plain'],
    );
  });

  test('backslash escapes the next character', () {
    expect(splitArgs(r'a\ b c'), ['a b', 'c']);
    expect(splitArgs(r'"a\"b"'), ['a"b']);
  });

  test('backslash is literal inside single quotes', () {
    expect(splitArgs(r"'C:\Games\x'"), [r'C:\Games\x']);
  });

  test('empty quoted strings are empty args', () {
    expect(splitArgs('a "" b'), ['a', '', 'b']);
  });

  test('an unclosed double quote throws', () {
    expect(
      () => splitArgs('--path "C:\\games'),
      throwsA(isA<FormatException>().having(
          (e) => e.message, 'message', contains('Unclosed'))),
    );
  });

  test('an unclosed single quote throws', () {
    expect(
      () => splitArgs("run 'two words"),
      throwsA(isA<FormatException>().having(
          (e) => e.message, 'message', contains('Unclosed'))),
    );
  });
}
