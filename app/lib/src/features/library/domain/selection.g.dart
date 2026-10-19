// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'selection.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Selected tile id: a game id, or a group id. Null means the detail pane is
/// closed. When a group is selected, the pane shows one of its members (see
/// [selectedGame]), so the selection represents "group X, showing member Y".

@ProviderFor(SelectedGameId)
final selectedGameIdProvider = SelectedGameIdProvider._();

/// Selected tile id: a game id, or a group id. Null means the detail pane is
/// closed. When a group is selected, the pane shows one of its members (see
/// [selectedGame]), so the selection represents "group X, showing member Y".
final class SelectedGameIdProvider
    extends $NotifierProvider<SelectedGameId, String?> {
  /// Selected tile id: a game id, or a group id. Null means the detail pane is
  /// closed. When a group is selected, the pane shows one of its members (see
  /// [selectedGame]), so the selection represents "group X, showing member Y".
  SelectedGameIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedGameIdProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedGameIdHash();

  @$internal
  @override
  SelectedGameId create() => SelectedGameId();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$selectedGameIdHash() => r'e2685676e241a9cf4a9308c32dbdc6c321bbc7ac';

/// Selected tile id: a game id, or a group id. Null means the detail pane is
/// closed. When a group is selected, the pane shows one of its members (see
/// [selectedGame]), so the selection represents "group X, showing member Y".

abstract class _$SelectedGameId extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The selected group, when the selected tile is a group.

@ProviderFor(selectedGroup)
final selectedGroupProvider = SelectedGroupProvider._();

/// The selected group, when the selected tile is a group.

final class SelectedGroupProvider
    extends $FunctionalProvider<GameGroup?, GameGroup?, GameGroup?>
    with $Provider<GameGroup?> {
  /// The selected group, when the selected tile is a group.
  SelectedGroupProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedGroupProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedGroupHash();

  @$internal
  @override
  $ProviderElement<GameGroup?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GameGroup? create(Ref ref) {
    return selectedGroup(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GameGroup? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GameGroup?>(value),
    );
  }
}

String _$selectedGroupHash() => r'4abe9579aa6eced998dc838173cfa41d58865aee';

/// The selected game from the full library, so a filter hiding it leaves the
/// pane open while a reload that drops its id closes the pane. When a group
/// is selected, this is the group's picked member.

@ProviderFor(selectedGame)
final selectedGameProvider = SelectedGameProvider._();

/// The selected game from the full library, so a filter hiding it leaves the
/// pane open while a reload that drops its id closes the pane. When a group
/// is selected, this is the group's picked member.

final class SelectedGameProvider
    extends $FunctionalProvider<Game?, Game?, Game?>
    with $Provider<Game?> {
  /// The selected game from the full library, so a filter hiding it leaves the
  /// pane open while a reload that drops its id closes the pane. When a group
  /// is selected, this is the group's picked member.
  SelectedGameProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedGameProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedGameHash();

  @$internal
  @override
  $ProviderElement<Game?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Game? create(Ref ref) {
    return selectedGame(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Game? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Game?>(value),
    );
  }
}

String _$selectedGameHash() => r'6df81fd47f84b95290308e4b8cbbbcd7e74869bb';
