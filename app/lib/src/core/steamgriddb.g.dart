// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'steamgriddb.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// SteamGridDB client built from the stored key, or null when no key is set.
/// Shares the overridable HTTP client the picker uses, so tests can fake it.

@ProviderFor(steamGridDbClient)
final steamGridDbClientProvider = SteamGridDbClientProvider._();

/// SteamGridDB client built from the stored key, or null when no key is set.
/// Shares the overridable HTTP client the picker uses, so tests can fake it.

final class SteamGridDbClientProvider
    extends
        $FunctionalProvider<
          SteamGridDbClient?,
          SteamGridDbClient?,
          SteamGridDbClient?
        >
    with $Provider<SteamGridDbClient?> {
  /// SteamGridDB client built from the stored key, or null when no key is set.
  /// Shares the overridable HTTP client the picker uses, so tests can fake it.
  SteamGridDbClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'steamGridDbClientProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$steamGridDbClientHash();

  @$internal
  @override
  $ProviderElement<SteamGridDbClient?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SteamGridDbClient? create(Ref ref) {
    return steamGridDbClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SteamGridDbClient? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SteamGridDbClient?>(value),
    );
  }
}

String _$steamGridDbClientHash() => r'cf8858ef3c0e248155bfcbe6f4efcc6491da5158';
