// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'running_games.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The launch phase of each game Tsumige can currently see.
///
/// Entries exist only between `starting` and `ended`: the `ended` callback
/// removes the game, so the button shows "Running" (or "Launching…") only
/// while the game's process is actually visible. Keep-alive: a launch
/// outlives the detail pane, and the entry must still be here when the game
/// exits, even if the pane was closed and reopened mid-session.

@ProviderFor(RunningGames)
final runningGamesProvider = RunningGamesProvider._();

/// The launch phase of each game Tsumige can currently see.
///
/// Entries exist only between `starting` and `ended`: the `ended` callback
/// removes the game, so the button shows "Running" (or "Launching…") only
/// while the game's process is actually visible. Keep-alive: a launch
/// outlives the detail pane, and the entry must still be here when the game
/// exits, even if the pane was closed and reopened mid-session.
final class RunningGamesProvider
    extends $NotifierProvider<RunningGames, Map<String, LaunchPhase>> {
  /// The launch phase of each game Tsumige can currently see.
  ///
  /// Entries exist only between `starting` and `ended`: the `ended` callback
  /// removes the game, so the button shows "Running" (or "Launching…") only
  /// while the game's process is actually visible. Keep-alive: a launch
  /// outlives the detail pane, and the entry must still be here when the game
  /// exits, even if the pane was closed and reopened mid-session.
  RunningGamesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runningGamesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runningGamesHash();

  @$internal
  @override
  RunningGames create() => RunningGames();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, LaunchPhase> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, LaunchPhase>>(value),
    );
  }
}

String _$runningGamesHash() => r'10bd9c6c815b1d3e953461e61da6ce75de6c0242';

/// The launch phase of each game Tsumige can currently see.
///
/// Entries exist only between `starting` and `ended`: the `ended` callback
/// removes the game, so the button shows "Running" (or "Launching…") only
/// while the game's process is actually visible. Keep-alive: a launch
/// outlives the detail pane, and the entry must still be here when the game
/// exits, even if the pane was closed and reopened mid-session.

abstract class _$RunningGames extends $Notifier<Map<String, LaunchPhase>> {
  Map<String, LaunchPhase> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<Map<String, LaunchPhase>, Map<String, LaunchPhase>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Map<String, LaunchPhase>, Map<String, LaunchPhase>>,
              Map<String, LaunchPhase>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
