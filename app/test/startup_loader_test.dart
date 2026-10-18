// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumige/main.dart';
import 'package:tsumige/src/core/model.dart' as core;
import 'package:tsumige/src/core/paths.dart' as core;
import 'package:tsumige/src/features/library/data/library_repository.dart';
import 'package:tsumige/src/utils/prefs/prefs_mixin.dart';
import 'package:tsumige/src/widgets/tsumige_logo.dart';

void main() {
  testWidgets('the startup loader is centred at 35% of the shorter side', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final temp = Directory.systemTemp.createTempSync('tsumige_logo_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
          libraryProvider.overrideWith(() => _PendingLibrary()),
        ],
        child: const TsumigeApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(TsumigeLogoShimmer), findsOneWidget);
    expect(tester.getSize(find.byType(ImageIcon)), const Size(210, 210));
    expect(
      tester.getCenter(find.byType(ImageIcon)),
      tester.getCenter(find.byType(Scaffold)),
    );
  });
}

class _PendingLibrary extends Library {
  @override
  Future<core.LoadedLibrary> build() => Completer<core.LoadedLibrary>().future;
}
