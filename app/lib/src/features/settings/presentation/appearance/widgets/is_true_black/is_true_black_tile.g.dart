// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'is_true_black_tile.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(IsTrueBlack)
final isTrueBlackProvider = IsTrueBlackProvider._();

final class IsTrueBlackProvider extends $NotifierProvider<IsTrueBlack, bool?> {
  IsTrueBlackProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'isTrueBlackProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$isTrueBlackHash();

  @$internal
  @override
  IsTrueBlack create() => IsTrueBlack();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool?>(value),
    );
  }
}

String _$isTrueBlackHash() => r'52866a9409c8dd8f7786764552754c58f337c84f';

abstract class _$IsTrueBlack extends $Notifier<bool?> {
  bool? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool?, bool?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool?, bool?>,
              bool?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
