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
      secondary: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black,
            border: Border.all(
              color: Theme.of(context).colorScheme.onSurface,
              width: 1.5,
            ),
          ),
        ),
      ),
      title: Text(context.l10n.pureBlackAmoled),
      onChanged: ref.read(isTrueBlackProvider.notifier).update,
      value: ref.watch(isTrueBlackProvider).ifNull(),
    );
  }
}
