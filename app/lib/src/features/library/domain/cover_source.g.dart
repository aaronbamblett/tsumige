// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cover_source.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Memoised cover-file existence check: each path hits the disk once, so
/// scrolling and slider drags never re-stat files every frame.

@ProviderFor(coverExists)
final coverExistsProvider = CoverExistsProvider._();

/// Memoised cover-file existence check: each path hits the disk once, so
/// scrolling and slider drags never re-stat files every frame.

final class CoverExistsProvider
    extends
        $FunctionalProvider<
          bool Function(String path),
          bool Function(String path),
          bool Function(String path)
        >
    with $Provider<bool Function(String path)> {
  /// Memoised cover-file existence check: each path hits the disk once, so
  /// scrolling and slider drags never re-stat files every frame.
  CoverExistsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'coverExistsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$coverExistsHash();

  @$internal
  @override
  $ProviderElement<bool Function(String path)> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  bool Function(String path) create(Ref ref) {
    return coverExists(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool Function(String path) value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool Function(String path)>(value),
    );
  }
}

String _$coverExistsHash() => r'64db10a28f6268e092315e223b08448c3e51baac';

/// The stat behind [artVersionProvider]; tests override it to count stats.

@ProviderFor(artVersionStat)
final artVersionStatProvider = ArtVersionStatProvider._();

/// The stat behind [artVersionProvider]; tests override it to count stats.

final class ArtVersionStatProvider
    extends
        $FunctionalProvider<
          String Function(String path),
          String Function(String path),
          String Function(String path)
        >
    with $Provider<String Function(String path)> {
  /// The stat behind [artVersionProvider]; tests override it to count stats.
  ArtVersionStatProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'artVersionStatProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$artVersionStatHash();

  @$internal
  @override
  $ProviderElement<String Function(String path)> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  String Function(String path) create(Ref ref) {
    return artVersionStat(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String Function(String path) value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String Function(String path)>(value),
    );
  }
}

String _$artVersionStatHash() => r'694c25af69cf098962d111db86b801706d69cfc9';

/// Memoised [artVersionOf], like [coverExists]: each path is stat'ed once,
/// and the art stores invalidate this provider after they write files.

@ProviderFor(artVersion)
final artVersionProvider = ArtVersionProvider._();

/// Memoised [artVersionOf], like [coverExists]: each path is stat'ed once,
/// and the art stores invalidate this provider after they write files.

final class ArtVersionProvider
    extends
        $FunctionalProvider<
          String Function(String path),
          String Function(String path),
          String Function(String path)
        >
    with $Provider<String Function(String path)> {
  /// Memoised [artVersionOf], like [coverExists]: each path is stat'ed once,
  /// and the art stores invalidate this provider after they write files.
  ArtVersionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'artVersionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$artVersionHash();

  @$internal
  @override
  $ProviderElement<String Function(String path)> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  String Function(String path) create(Ref ref) {
    return artVersion(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String Function(String path) value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String Function(String path)>(value),
    );
  }
}

String _$artVersionHash() => r'ee89486212ea20f21dfbe7e77c0934a652b02b5f';

/// The cover width the grid decodes from. It follows [coverWidthProvider]
/// 250 ms after the slider stops, so during a drag tiles keep their current
/// image and scale it instead of re-decoding every step.

@ProviderFor(SettledCoverWidth)
final settledCoverWidthProvider = SettledCoverWidthProvider._();

/// The cover width the grid decodes from. It follows [coverWidthProvider]
/// 250 ms after the slider stops, so during a drag tiles keep their current
/// image and scale it instead of re-decoding every step.
final class SettledCoverWidthProvider
    extends $NotifierProvider<SettledCoverWidth, int> {
  /// The cover width the grid decodes from. It follows [coverWidthProvider]
  /// 250 ms after the slider stops, so during a drag tiles keep their current
  /// image and scale it instead of re-decoding every step.
  SettledCoverWidthProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settledCoverWidthProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settledCoverWidthHash();

  @$internal
  @override
  SettledCoverWidth create() => SettledCoverWidth();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$settledCoverWidthHash() => r'bb96a516955cc1e2cf9c70e3ff413ef9a36b9a41';

/// The cover width the grid decodes from. It follows [coverWidthProvider]
/// 250 ms after the slider stops, so during a drag tiles keep their current
/// image and scale it instead of re-decoding every step.

abstract class _$SettledCoverWidth extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Search text for the library grid. Local state, not persisted.

@ProviderFor(LibrarySearch)
final librarySearchProvider = LibrarySearchProvider._();

/// Search text for the library grid. Local state, not persisted.
final class LibrarySearchProvider
    extends $NotifierProvider<LibrarySearch, String> {
  /// Search text for the library grid. Local state, not persisted.
  LibrarySearchProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'librarySearchProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$librarySearchHash();

  @$internal
  @override
  LibrarySearch create() => LibrarySearch();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$librarySearchHash() => r'67281fc80b74b09d8dc9f6fe16fa94dd9bdaf55b';

/// Search text for the library grid. Local state, not persisted.

abstract class _$LibrarySearch extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Developer filter from a developer link in the pane; null means no filter.
/// Local state, not persisted, like the search text.

@ProviderFor(DeveloperFilter)
final developerFilterProvider = DeveloperFilterProvider._();

/// Developer filter from a developer link in the pane; null means no filter.
/// Local state, not persisted, like the search text.
final class DeveloperFilterProvider
    extends $NotifierProvider<DeveloperFilter, Developer?> {
  /// Developer filter from a developer link in the pane; null means no filter.
  /// Local state, not persisted, like the search text.
  DeveloperFilterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'developerFilterProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$developerFilterHash();

  @$internal
  @override
  DeveloperFilter create() => DeveloperFilter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Developer? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Developer?>(value),
    );
  }
}

String _$developerFilterHash() => r'3d100f4f16cc4793481f774e3268849bdbc0dc24';

/// Developer filter from a developer link in the pane; null means no filter.
/// Local state, not persisted, like the search text.

abstract class _$DeveloperFilter extends $Notifier<Developer?> {
  Developer? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Developer?, Developer?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Developer?, Developer?>,
              Developer?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// `applyGroupedQuery` over the loaded library and every toolbar
/// preference: group members collapse into one tile per group.

@ProviderFor(visibleTiles)
final visibleTilesProvider = VisibleTilesProvider._();

/// `applyGroupedQuery` over the loaded library and every toolbar
/// preference: group members collapse into one tile per group.

final class VisibleTilesProvider
    extends
        $FunctionalProvider<
          List<LibraryTile>,
          List<LibraryTile>,
          List<LibraryTile>
        >
    with $Provider<List<LibraryTile>> {
  /// `applyGroupedQuery` over the loaded library and every toolbar
  /// preference: group members collapse into one tile per group.
  VisibleTilesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'visibleTilesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$visibleTilesHash();

  @$internal
  @override
  $ProviderElement<List<LibraryTile>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<LibraryTile> create(Ref ref) {
    return visibleTiles(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<LibraryTile> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<LibraryTile>>(value),
    );
  }
}

String _$visibleTilesHash() => r'86a7f3e8be27827cf46334a5c5a1e007e514f4d9';
