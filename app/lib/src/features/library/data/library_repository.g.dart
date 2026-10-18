// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app's data folder. Resolves from the environment and is overridable in
/// tests — tests must never touch the real data folder.

@ProviderFor(dataDir)
final dataDirProvider = DataDirProvider._();

/// The app's data folder. Resolves from the environment and is overridable in
/// tests — tests must never touch the real data folder.

final class DataDirProvider
    extends $FunctionalProvider<core.DataDir, core.DataDir, core.DataDir>
    with $Provider<core.DataDir> {
  /// The app's data folder. Resolves from the environment and is overridable in
  /// tests — tests must never touch the real data folder.
  DataDirProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dataDirProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dataDirHash();

  @$internal
  @override
  $ProviderElement<core.DataDir> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  core.DataDir create(Ref ref) {
    return dataDir(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(core.DataDir value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<core.DataDir>(value),
    );
  }
}

String _$dataDirHash() => r'f19b681bb1a86713ad324cfb61c5884ae8f32da6';

@ProviderFor(libraryRepository)
final libraryRepositoryProvider = LibraryRepositoryProvider._();

final class LibraryRepositoryProvider
    extends
        $FunctionalProvider<
          LibraryRepository,
          LibraryRepository,
          LibraryRepository
        >
    with $Provider<LibraryRepository> {
  LibraryRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryRepositoryHash();

  @$internal
  @override
  $ProviderElement<LibraryRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LibraryRepository create(Ref ref) {
    return libraryRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LibraryRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LibraryRepository>(value),
    );
  }
}

String _$libraryRepositoryHash() => r'6a6b2c19fd123e1843c1edda8a90da9aa2b82283';

/// The only code that loads the library, through [libraryRepositoryProvider].

@ProviderFor(Library)
final libraryProvider = LibraryProvider._();

/// The only code that loads the library, through [libraryRepositoryProvider].
final class LibraryProvider
    extends $AsyncNotifierProvider<Library, core.LoadedLibrary> {
  /// The only code that loads the library, through [libraryRepositoryProvider].
  LibraryProvider._()
    : super(
        from: null,
        argument: null,
        retry: _noLibraryRetry,
        name: r'libraryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryHash();

  @$internal
  @override
  Library create() => Library();
}

String _$libraryHash() => r'1ae40f463bd72aab0d3a92e570cfdd907c1c02aa';

/// The only code that loads the library, through [libraryRepositoryProvider].

abstract class _$Library extends $AsyncNotifier<core.LoadedLibrary> {
  FutureOr<core.LoadedLibrary> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<core.LoadedLibrary>, core.LoadedLibrary>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<core.LoadedLibrary>, core.LoadedLibrary>,
              AsyncValue<core.LoadedLibrary>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
