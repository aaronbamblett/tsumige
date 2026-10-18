// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runner_detection.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Detected Wine runners. Rescan with `ref.invalidate(wineRunnersProvider)`.

@ProviderFor(wineRunners)
final wineRunnersProvider = WineRunnersProvider._();

/// Detected Wine runners. Rescan with `ref.invalidate(wineRunnersProvider)`.

final class WineRunnersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<WineRunner>>,
          List<WineRunner>,
          FutureOr<List<WineRunner>>
        >
    with $FutureModifier<List<WineRunner>>, $FutureProvider<List<WineRunner>> {
  /// Detected Wine runners. Rescan with `ref.invalidate(wineRunnersProvider)`.
  WineRunnersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'wineRunnersProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$wineRunnersHash();

  @$internal
  @override
  $FutureProviderElement<List<WineRunner>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<WineRunner>> create(Ref ref) {
    return wineRunners(ref);
  }
}

String _$wineRunnersHash() => r'13aa0912c1d1417c6e1ddcb7e54d0ae5ff3eee5d';

/// Detected Proton runners. Rescan with `ref.invalidate(protonRunnersProvider)`.

@ProviderFor(protonRunners)
final protonRunnersProvider = ProtonRunnersProvider._();

/// Detected Proton runners. Rescan with `ref.invalidate(protonRunnersProvider)`.

final class ProtonRunnersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ProtonRunner>>,
          List<ProtonRunner>,
          FutureOr<List<ProtonRunner>>
        >
    with
        $FutureModifier<List<ProtonRunner>>,
        $FutureProvider<List<ProtonRunner>> {
  /// Detected Proton runners. Rescan with `ref.invalidate(protonRunnersProvider)`.
  ProtonRunnersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'protonRunnersProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$protonRunnersHash();

  @$internal
  @override
  $FutureProviderElement<List<ProtonRunner>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ProtonRunner>> create(Ref ref) {
    return protonRunners(ref);
  }
}

String _$protonRunnersHash() => r'91ba3872630d4caac6ce380ef2349cc86cee250a';

/// Detected Steam prefixes. Rescan with `ref.invalidate(steamPrefixesProvider)`.

@ProviderFor(steamPrefixes)
final steamPrefixesProvider = SteamPrefixesProvider._();

/// Detected Steam prefixes. Rescan with `ref.invalidate(steamPrefixesProvider)`.

final class SteamPrefixesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<SteamPrefix>>,
          List<SteamPrefix>,
          FutureOr<List<SteamPrefix>>
        >
    with
        $FutureModifier<List<SteamPrefix>>,
        $FutureProvider<List<SteamPrefix>> {
  /// Detected Steam prefixes. Rescan with `ref.invalidate(steamPrefixesProvider)`.
  SteamPrefixesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'steamPrefixesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$steamPrefixesHash();

  @$internal
  @override
  $FutureProviderElement<List<SteamPrefix>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<SteamPrefix>> create(Ref ref) {
    return steamPrefixes(ref);
  }
}

String _$steamPrefixesHash() => r'33b4b03a59841373372d4da973bfa68efb0e329c';
