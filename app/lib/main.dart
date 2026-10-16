// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:vnl_core/vnl_core.dart';

void main() {
  runApp(const VnlApp());
}

class VnlApp extends StatelessWidget {
  const VnlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(body: Center(child: Text('vnl core $vnlVersion'))),
    );
  }
}
