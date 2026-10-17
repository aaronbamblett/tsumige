// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'launch_actions.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(launchActions)
final launchActionsProvider = LaunchActionsProvider._();

final class LaunchActionsProvider
    extends $FunctionalProvider<LaunchActions, LaunchActions, LaunchActions>
    with $Provider<LaunchActions> {
  LaunchActionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'launchActionsProvider',
        isAutoDispose: true,
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

String _$launchActionsHash() => r'de7f7ec2858aa3cdaf773d25c2849db6c2c1f615';
