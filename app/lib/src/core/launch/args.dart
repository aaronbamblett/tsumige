// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

List<String> splitArgs(String input) {
  final result = <String>[];
  final current = StringBuffer();
  var inArg = false;
  var quote = '';
  var i = 0;
  bool isSpace(String c) =>
      c == ' ' ||
      c == '\t' ||
      c == '\n' ||
      c == '\r' ||
      c == '\f' ||
      c == '\v';
  while (i < input.length) {
    final c = input[i];
    if (quote == "'") {
      if (c == "'") {
        quote = '';
      } else {
        current.write(c);
      }
      i++;
      continue;
    }
    if (quote == '"') {
      if (c == '"') {
        quote = '';
        i++;
        continue;
      }
      if (c == '\\' && i + 1 < input.length) {
        current.write(input[i + 1]);
        i += 2;
        continue;
      }
      current.write(c);
      i++;
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      inArg = true;
      i++;
      continue;
    }
    if (c == '\\' && i + 1 < input.length) {
      current.write(input[i + 1]);
      i += 2;
      continue;
    }
    if (isSpace(c)) {
      if (inArg) {
        result.add(current.toString());
        current.clear();
        inArg = false;
      }
      i++;
      continue;
    }
    current.write(c);
    inArg = true;
    i++;
  }
  if (quote == "'") {
    throw const FormatException('Unclosed single quote in arguments');
  }
  if (quote == '"') {
    throw const FormatException('Unclosed double quote in arguments');
  }
  if (inArg) result.add(current.toString());
  return result;
}
