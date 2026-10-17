// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'running_games.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The ids of games running right now. A second game can launch while one
/// runs, so this is a set rather than a single id.

@ProviderFor(RunningGames)
final runningGamesProvider = RunningGamesProvider._();

/// The ids of games running right now. A second game can launch while one
/// runs, so this is a set rather than a single id.
final class RunningGamesProvider
    extends $NotifierProvider<RunningGames, Set<String>> {
  /// The ids of games running right now. A second game can launch while one
  /// runs, so this is a set rather than a single id.
  RunningGamesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runningGamesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runningGamesHash();

  @$internal
  @override
  RunningGames create() => RunningGames();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$runningGamesHash() => r'26297313707fd4e05fbc05460146022d07382409';

/// The ids of games running right now. A second game can launch while one
/// runs, so this is a set rather than a single id.

abstract class _$RunningGames extends $Notifier<Set<String>> {
  Set<String> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
