// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttertoast/fluttertoast.dart' hide Toast;
import 'package:tsumige/src/utils/toast.dart';

void main() {
  testWidgets('toast shows on screen', (tester) async {
    late BuildContext toastContext;
    await tester.pumpWidget(
      MaterialApp(
        builder: FToastBuilder(),
        home: Builder(
          builder: (context) {
            toastContext = context;
            return const SizedBox();
          },
        ),
      ),
    );
    Toast(toastContext).show('hello');
    await tester.pump();
    expect(find.text('hello'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });
}
