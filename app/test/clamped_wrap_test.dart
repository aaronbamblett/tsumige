// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumige/src/widgets/clamped_wrap.dart';

RenderClampedWrap _renderOf(WidgetTester tester) =>
    tester.renderObject<RenderClampedWrap>(find.byType(ClampedWrap));

Future<void> _pumpWrap(WidgetTester tester, ClampedWrap wrap) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 320, child: wrap),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _box(int i) => SizedBox(
      key: ValueKey('child-$i'),
      width: 100,
      height: 24,
      child: ColoredBox(color: Colors.blue.shade100),
    );

void main() {
  testWidgets('two rows of 100 px children show 6 and report overflow',
      (tester) async {
    final overflows = <bool>[];
    await _pumpWrap(
      tester,
      ClampedWrap(
        spacing: 6,
        runSpacing: 8,
        maxRows: 2,
        onOverflowChanged: overflows.add,
        children: [for (var i = 0; i < 10; i++) _box(i)],
      ),
    );
    final render = _renderOf(tester);
    expect(render.visibleLeadingCount, 6);
    expect(render.overflowed, isTrue);
    expect(overflows, [true]);
    expect(render.size.height, 24 * 2 + 8);
  });

  testWidgets('trailing stays last and drops one more leading child',
      (tester) async {
    final overflows = <bool>[];
    await _pumpWrap(
      tester,
      ClampedWrap(
        spacing: 6,
        runSpacing: 8,
        maxRows: 2,
        onOverflowChanged: overflows.add,
        trailing: const SizedBox(
          key: ValueKey('trailing'),
          width: 60,
          height: 24,
        ),
        children: [for (var i = 0; i < 10; i++) _box(i)],
      ),
    );
    final render = _renderOf(tester);
    expect(render.visibleLeadingCount, 5);
    expect(render.overflowed, isTrue);
    expect(overflows, [true]);
    final trailingCenter =
        tester.getCenter(find.byKey(const ValueKey('trailing')));
    final fifthCenter = tester.getCenter(find.byKey(const ValueKey('child-4')));
    expect(trailingCenter.dy, fifthCenter.dy);
    expect(trailingCenter.dx, greaterThan(fifthCenter.dx));
  });

  testWidgets('null maxRows shows everything', (tester) async {
    final overflows = <bool>[];
    await _pumpWrap(
      tester,
      ClampedWrap(
        spacing: 6,
        runSpacing: 8,
        onOverflowChanged: overflows.add,
        trailing: const SizedBox(
          key: ValueKey('trailing'),
          width: 60,
          height: 24,
        ),
        children: [for (var i = 0; i < 10; i++) _box(i)],
      ),
    );
    final render = _renderOf(tester);
    expect(render.visibleLeadingCount, 10);
    expect(render.overflowed, isFalse);
    expect(overflows, isEmpty);
    expect(render.size.height, 24 * 4 + 8 * 3);
  });
}
