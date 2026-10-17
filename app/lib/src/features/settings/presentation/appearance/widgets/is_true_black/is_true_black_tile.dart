// Copyright (c) 2026 Contributors to the Suwayomi project
// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/pref_keys.dart';
import '../../../../../../utils/extensions/bool.dart';
import '../../../../../../utils/extensions/l10n.dart';
import '../../../../../../utils/prefs/prefs_mixin.dart';

part 'is_true_black_tile.g.dart';

@riverpod
class IsTrueBlack extends _$IsTrueBlack with PrefsMixin<bool?> {
  @override
  bool? build() => initNullableBool(PrefKey.trueBlack);

  void update(bool? value) => state = value;
}

class IsTrueBlackTile extends HookConsumerWidget {
  const IsTrueBlackTile({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      controlAffinity: ListTileControlAffinity.trailing,
      secondary: const Icon(Icons.circle_rounded, color: Colors.black),
      title: Text(context.l10n.pureBlackAmoled),
      onChanged: ref.read(isTrueBlackProvider.notifier).update,
      value: ref.watch(isTrueBlackProvider).ifNull(),
    );
  }
}
