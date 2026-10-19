// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/groups.dart';
import '../../../core/model.dart';
import '../../../core/store.dart';
import '../../../utils/toast.dart';
import '../data/library_repository.dart';
import 'selection.dart';

part 'game_editor.g.dart';

const String changedOnDiskMessage =
    "The library changed outside Tsumige, so that change wasn't saved. "
    "It's reloaded now.";

/// Every pane edit saves through here: apply [change] to the game with
/// [gameId], then save. The id is captured when the edit starts, never the
/// currently selected game, so a blur-save after switching games still lands
/// on the original game.
@Riverpod(keepAlive: true)
GameEditor gameEditor(Ref ref) => GameEditor(ref);

class GameEditor {
  GameEditor(this._ref);

  final Ref _ref;

  Future<void> update(String gameId, void Function(Game) change,
      {BuildContext? context}) async {
    final loaded = _ref.read(libraryProvider).value;
    if (loaded == null) return;
    final index = loaded.library.games.indexWhere((g) => g.id == gameId);
    if (index < 0) return;
    change(loaded.library.games[index]);
    try {
      await _ref.read(libraryRepositoryProvider).save(loaded);
    } on ChangedOnDisk {
      _ref.invalidate(libraryProvider);
      if (context?.mounted == false) return;
      _tell(context, changedOnDiskMessage, error: false);
      return;
    } catch (e) {
      _ref.invalidate(libraryProvider);
      if (context?.mounted == false) return;
      _tell(context, '$e', error: true);
      return;
    }
    _ref.invalidate(libraryProvider);
  }

  /// Appends a new game (the add dialog's save path) and saves.
  Future<void> add(Game game, {BuildContext? context}) =>
      addAll([game], context: context);

  /// Appends new games and saves once for the whole batch.
  Future<void> addAll(List<Game> games, {BuildContext? context}) async {
    final loaded = _ref.read(libraryProvider).value;
    if (loaded == null) return;
    loaded.library.games.addAll(games);
    try {
      await _ref.read(libraryRepositoryProvider).save(loaded);
    } on ChangedOnDisk {
      _ref.invalidate(libraryProvider);
      if (context?.mounted == false) return;
      _tell(context, changedOnDiskMessage, error: false);
      return;
    } catch (e) {
      _ref.invalidate(libraryProvider);
      if (context?.mounted == false) return;
      _tell(context, '$e', error: true);
      return;
    }
    _ref.invalidate(libraryProvider);
  }

  /// Removes the game (already moved to trash by the caller) and saves.
  /// The game also drops out of its group; a group left with one member
  /// dissolves. When the open group dissolves, the pane stays on the shown
  /// member when it still exists.
  Future<void> remove(String gameId, {BuildContext? context}) async {
    final loaded = _ref.read(libraryProvider).value;
    if (loaded == null) return;
    final selectedId = _ref.read(selectedGameIdProvider);
    Game? shown;
    var selectedWasGroup = false;
    if (selectedId != null) {
      for (final group in loaded.library.groups) {
        if (group.id == selectedId) {
          selectedWasGroup = true;
          final byId = {for (final g in loaded.library.games) g.id: g};
          shown = resolvePickedMember(group, byId);
        }
      }
    }
    loaded.library.games.removeWhere((g) => g.id == gameId);
    normalizeGroups(loaded.library);
    try {
      await _ref.read(libraryRepositoryProvider).save(loaded);
    } on ChangedOnDisk {
      _ref.invalidate(libraryProvider);
      if (context?.mounted == false) return;
      _tell(context, changedOnDiskMessage, error: false);
      return;
    } catch (e) {
      _ref.invalidate(libraryProvider);
      if (context?.mounted == false) return;
      _tell(context, '$e', error: true);
      return;
    }
    if (_ref.read(selectedGameIdProvider) == gameId) {
      _ref.read(selectedGameIdProvider.notifier).clear();
    } else if (selectedWasGroup &&
        loaded.library.groups.every((gr) => gr.id != selectedId)) {
      final selection = _ref.read(selectedGameIdProvider.notifier);
      if (shown != null &&
          shown.id != gameId &&
          loaded.library.games.any((g) => g.id == shown!.id)) {
        selection.select(shown.id);
      } else {
        selection.clear();
      }
    }
    _ref.invalidate(libraryProvider);
  }

  /// Remembers [memberId] as the picked member of [groupId] and saves.
  Future<void> pickGroupMember(String groupId, String memberId,
      {BuildContext? context}) async {
    final loaded = _ref.read(libraryProvider).value;
    if (loaded == null) return;
    GameGroup? group;
    for (final gr in loaded.library.groups) {
      if (gr.id == groupId) group = gr;
    }
    if (group == null || !group.memberIds.contains(memberId)) return;
    group.lastPickedId = memberId;
    try {
      await _ref.read(libraryRepositoryProvider).save(loaded);
    } on ChangedOnDisk {
      _ref.invalidate(libraryProvider);
      if (context?.mounted == false) return;
      _tell(context, changedOnDiskMessage, error: false);
      return;
    } catch (e) {
      _ref.invalidate(libraryProvider);
      if (context?.mounted == false) return;
      _tell(context, '$e', error: true);
      return;
    }
    _ref.invalidate(libraryProvider);
  }

  void _tell(BuildContext? context, String message, {required bool error}) {
    if (context == null || !context.mounted) return;
    if (error) {
      Toast(context).showError(message);
    } else {
      Toast(context).show(message);
    }
  }
}


/// Cover picker seam: tests override this so no real dialog ever opens.
@riverpod
Future<String?> Function() coverPicker(Ref ref) => pickCoverFile;

Future<String?> pickCoverFile() async {
  final picked = await FilePicker.pickFiles(
    dialogTitle: 'Choose image',
    type: FileType.custom,
    allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
  );
  if (picked.isEmpty) return null;
  return picked.first.path;
}

enum PathPickMode { file, folder }

/// Path picker seam: tests override this so no real dialog ever opens.
@riverpod
Future<String?> Function(
        {String? initialDirectory, PathPickMode mode})
    pathPicker(Ref ref) => pickPath;

Future<String?> pickPath(
    {String? initialDirectory, PathPickMode mode = PathPickMode.file}) async {
  switch (mode) {
    case PathPickMode.folder:
      return FilePicker.getDirectoryPath(initialDirectory: initialDirectory);
    case PathPickMode.file:
      final picked = await FilePicker.pickFiles(
        initialDirectory: initialDirectory,
        type: FileType.any,
      );
      if (picked.isEmpty) return null;
      return picked.first.path;
  }
}
