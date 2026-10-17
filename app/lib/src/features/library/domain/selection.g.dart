// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'selection.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Selected game id; null means the detail pane is closed.

@ProviderFor(SelectedGameId)
final selectedGameIdProvider = SelectedGameIdProvider._();

/// Selected game id; null means the detail pane is closed.
final class SelectedGameIdProvider
    extends $NotifierProvider<SelectedGameId, String?> {
  /// Selected game id; null means the detail pane is closed.
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

/// Selected game id; null means the detail pane is closed.

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

/// The selected game from the full library, so a filter hiding it leaves the
/// pane open while a reload that drops its id closes the pane.

@ProviderFor(selectedGame)
final selectedGameProvider = SelectedGameProvider._();

/// The selected game from the full library, so a filter hiding it leaves the
/// pane open while a reload that drops its id closes the pane.

final class SelectedGameProvider
    extends $FunctionalProvider<Game?, Game?, Game?>
    with $Provider<Game?> {
  /// The selected game from the full library, so a filter hiding it leaves the
  /// pane open while a reload that drops its id closes the pane.
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

String _$selectedGameHash() => r'088d0c97498035c00cfadff214e7d9a645b7532d';
