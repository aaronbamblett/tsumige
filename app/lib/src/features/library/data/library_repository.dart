// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vnl_core/vnl_core.dart' as core;

part 'library_repository.g.dart';

/// The app's data folder. Resolves from the environment and is overridable in
/// tests — tests must never touch the real data folder.
@Riverpod(keepAlive: true)
core.DataDir dataDir(Ref ref) => core.DataDir.resolve(Platform.environment);

/// The single seam through which the app reaches the library file. Tests
/// override it with a fake.
abstract class LibraryRepository {
  Future<core.LoadedLibrary> load();
  Future<void> save(core.LoadedLibrary loaded);
  Future<core.RatingReport> refreshRatings(core.LoadedLibrary loaded);
  Future<core.ThumbReport> ensureThumbnails(core.Library library);
}

class IoLibraryRepository implements LibraryRepository {
  IoLibraryRepository(this.dir);

  final core.DataDir dir;

  @override
  Future<core.LoadedLibrary> load() => core.loadLibrary(dir);

  @override
  Future<void> save(core.LoadedLibrary loaded) =>
      core.saveLibrary(dir, loaded);

  @override
  Future<core.RatingReport> refreshRatings(core.LoadedLibrary loaded) =>
      core.refreshRatings(loaded, core.VndbClient());

  @override
  Future<core.ThumbReport> ensureThumbnails(core.Library library) =>
      core.ensureThumbnails(dir, library);
}

@Riverpod(keepAlive: true)
LibraryRepository libraryRepository(Ref ref) =>
    IoLibraryRepository(ref.watch(dataDirProvider));

/// The only code that loads the library, through [libraryRepositoryProvider].
@Riverpod(keepAlive: true)
class Library extends _$Library {
  @override
  Future<core.LoadedLibrary> build() =>
      ref.watch(libraryRepositoryProvider).load();

  Future<void> reload() async {
    state = const AsyncLoading();
    state =
        await AsyncValue.guard(() => ref.read(libraryRepositoryProvider).load());
  }
}
