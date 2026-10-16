// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:args/args.dart';
import 'package:vnl_core/vnl_core.dart';

void main(List<String> arguments) {
  final parser = ArgParser()..addFlag('version', abbr: 'v', negatable: false);
  final results = parser.parse(arguments);
  if (results['version'] as bool) {
    print('vnl $vnlVersion');
    return;
  }
  print(parser.usage);
}
