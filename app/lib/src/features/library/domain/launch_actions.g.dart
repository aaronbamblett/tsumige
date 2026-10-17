// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'launch_actions.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// `umu-run` resolved from PATH. A seam so tests can force it missing.

@ProviderFor(umuRunPath)
final umuRunPathProvider = UmuRunPathProvider._();

/// `umu-run` resolved from PATH. A seam so tests can force it missing.

final class UmuRunPathProvider
    extends $FunctionalProvider<String?, String?, String?>
    with $Provider<String?> {
  /// `umu-run` resolved from PATH. A seam so tests can force it missing.
  UmuRunPathProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'umuRunPathProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$umuRunPathHash();

  @$internal
  @override
  $ProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String? create(Ref ref) {
    return umuRunPath(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$umuRunPathHash() => r'1846c95eef84c078dcf9d7cb76bb7666cea053fd';

/// The real game runner, wired to the data folder and the repository.
/// Tests override this with a fake that never starts a process.

@ProviderFor(gameRunner)
final gameRunnerProvider = GameRunnerProvider._();

/// The real game runner, wired to the data folder and the repository.
/// Tests override this with a fake that never starts a process.

final class GameRunnerProvider
    extends $FunctionalProvider<GameRunner, GameRunner, GameRunner>
    with $Provider<GameRunner> {
  /// The real game runner, wired to the data folder and the repository.
  /// Tests override this with a fake that never starts a process.
  GameRunnerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'gameRunnerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$gameRunnerHash();

  @$internal
  @override
  $ProviderElement<GameRunner> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GameRunner create(Ref ref) {
    return gameRunner(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GameRunner value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GameRunner>(value),
    );
  }
}

String _$gameRunnerHash() => r'57fb81a2ec4fb413774c746ce5b0421f0fd35c2f';

/// The session store behind [gameRunnerProvider], shared with startup
/// recovery so both write through the repository.

@ProviderFor(sessionStore)
final sessionStoreProvider = SessionStoreProvider._();

/// The session store behind [gameRunnerProvider], shared with startup
/// recovery so both write through the repository.

final class SessionStoreProvider
    extends $FunctionalProvider<SessionStore, SessionStore, SessionStore>
    with $Provider<SessionStore> {
  /// The session store behind [gameRunnerProvider], shared with startup
  /// recovery so both write through the repository.
  SessionStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionStoreHash();

  @$internal
  @override
  $ProviderElement<SessionStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SessionStore create(Ref ref) {
    return sessionStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SessionStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SessionStore>(value),
    );
  }
}

String _$sessionStoreHash() => r'cf11a73a6e8bdb26abefb50822e3e75285813c1a';

/// Picks an exe to run inside the game's prefix, starting in the game exe's
/// folder when one exists. Null means the dialog was cancelled.

@ProviderFor(exePicker)
final exePickerProvider = ExePickerProvider._();

/// Picks an exe to run inside the game's prefix, starting in the game exe's
/// folder when one exists. Null means the dialog was cancelled.

final class ExePickerProvider
    extends
        $FunctionalProvider<
          Future<String?> Function(core.Game game),
          Future<String?> Function(core.Game game),
          Future<String?> Function(core.Game game)
        >
    with $Provider<Future<String?> Function(core.Game game)> {
  /// Picks an exe to run inside the game's prefix, starting in the game exe's
  /// folder when one exists. Null means the dialog was cancelled.
  ExePickerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'exePickerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$exePickerHash();

  @$internal
  @override
  $ProviderElement<Future<String?> Function(core.Game game)> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Future<String?> Function(core.Game game) create(Ref ref) {
    return exePicker(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Future<String?> Function(core.Game game) value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<Future<String?> Function(core.Game game)>(value),
    );
  }
}

String _$exePickerHash() => r'0453e8968351eb34967291a3eb8a9f3059a9fdd0';

/// Keep-alive: a launch runs for the whole play session, and `_run` reports
/// its end through this ref. An auto-dispose ref could be dead by then.

@ProviderFor(launchActions)
final launchActionsProvider = LaunchActionsProvider._();

/// Keep-alive: a launch runs for the whole play session, and `_run` reports
/// its end through this ref. An auto-dispose ref could be dead by then.

final class LaunchActionsProvider
    extends $FunctionalProvider<LaunchActions, LaunchActions, LaunchActions>
    with $Provider<LaunchActions> {
  /// Keep-alive: a launch runs for the whole play session, and `_run` reports
  /// its end through this ref. An auto-dispose ref could be dead by then.
  LaunchActionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'launchActionsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$launchActionsHash();

  @$internal
  @override
  $ProviderElement<LaunchActions> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LaunchActions create(Ref ref) {
    return launchActions(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LaunchActions value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LaunchActions>(value),
    );
  }
}

String _$launchActionsHash() => r'd62246bf38c6e035ba0b42ee721702d2ee054445';
