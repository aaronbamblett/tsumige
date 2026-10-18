// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/covers.dart';
import '../../../../core/model.dart';
import '../../../../core/trash.dart';
import '../../data/library_repository.dart';
import '../../domain/cover_source.dart';
import '../../domain/game_editor.dart';

/// Stores [bytes] as the game's cover and records [source] (a VNDB url, or
/// `file` for a local file). A new image starts at the default position, so
/// any saved [alignment] replaces the old one and null clears it. Image
/// caches follow the file version, so no manual eviction is needed.
Future<void> storeCoverBytes(
  BuildContext context,
  WidgetRef ref,
  Game game,
  List<int> bytes,
  String source, [
  Alignment? alignment,
]) async {
  final dir = ref.read(dataDirProvider);
  final name = await storeOriginal(dir, game.id, Uint8List.fromList(bytes));
  if (!context.mounted) return;
  await ref.read(gameEditorProvider).update(game.id, (g) {
    g.cover = name;
    g.coverSource = source;
    g.coverAlignment = alignment;
  }, context: context);
  await generateThumbnails(dir, [(game.id, name)]);
  ref.invalidate(coverExistsProvider);
  ref.invalidate(artVersionProvider);
}

Future<void> storeBackgroundBytes(
  BuildContext context,
  WidgetRef ref,
  Game game,
  List<int> bytes,
  String source, [
  Alignment? alignment,
]) async {
  final dir = ref.read(dataDirProvider);
  final name = await storeBackground(dir, game.id, Uint8List.fromList(bytes));
  if (!context.mounted) return;
  await ref.read(gameEditorProvider).update(game.id, (g) {
    g.background = name;
    g.backgroundSource = source;
    g.backgroundAlignment = alignment;
  }, context: context);
  ref.invalidate(coverExistsProvider);
  ref.invalidate(artVersionProvider);
}

/// Drops the pane background: its file moves to the trash folder and the
/// game falls back to its cover.
Future<void> clearBackground(
  BuildContext context,
  WidgetRef ref,
  Game game,
) async {
  final dir = ref.read(dataDirProvider);
  await trashBackground(dir, game);
  if (!context.mounted) return;
  await ref.read(gameEditorProvider).update(game.id, (g) {
    g.background = null;
    g.backgroundSource = null;
    g.backgroundAlignment = null;
  }, context: context);
  ref.invalidate(coverExistsProvider);
  ref.invalidate(artVersionProvider);
}
