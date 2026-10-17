// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/covers.dart';
import '../../../../core/model.dart';
import '../../../../core/trash.dart';
import '../../data/library_repository.dart';
import '../../domain/cover_source.dart';
import '../../domain/game_editor.dart';

Future<void> storeCoverBytes(
  BuildContext context,
  WidgetRef ref,
  Game game,
  List<int> bytes,
) async {
  final dir = ref.read(dataDirProvider);
  final name = await storeOriginal(dir, game.id, Uint8List.fromList(bytes));
  if (!context.mounted) return;
  await ref
      .read(gameEditorProvider)
      .update(game.id, (g) => g.cover = name, context: context);
  await generateThumbnails(dir, [(game.id, name)]);
  ref.invalidate(coverExistsProvider);
  for (final width in thumbWidths) {
    await FileImage(File(thumbPath(dir, game.id, width))).evict();
  }
  await FileImage(File(p.join(dir.coversOriginal.path, name))).evict();
}

Future<void> storeBackgroundBytes(
  BuildContext context,
  WidgetRef ref,
  Game game,
  List<int> bytes,
) async {
  final dir = ref.read(dataDirProvider);
  final name = await storeBackground(dir, game.id, Uint8List.fromList(bytes));
  if (!context.mounted) return;
  await ref
      .read(gameEditorProvider)
      .update(game.id, (g) => g.background = name, context: context);
  ref.invalidate(coverExistsProvider);
  await FileImage(File(p.join(dir.coversBackground.path, name))).evict();
}

/// Drops the pane background: its file moves to the trash folder and the
/// game falls back to its cover.
Future<void> clearBackground(
  BuildContext context,
  WidgetRef ref,
  Game game,
) async {
  final dir = ref.read(dataDirProvider);
  final background = game.background;
  await trashBackground(dir, game);
  if (background != null && background.isNotEmpty) {
    await FileImage(File(p.join(dir.coversBackground.path, background)))
        .evict();
  }
  if (!context.mounted) return;
  await ref
      .read(gameEditorProvider)
      .update(game.id, (g) => g.background = null, context: context);
  ref.invalidate(coverExistsProvider);
}
