import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_services.dart';
import '../../application/ports/backend_capabilities_port.dart';
import '../app_shell/providers/session_provider.dart';

class BackendFeatures {
  const BackendFeatures(this.sources);
  final Map<String, dynamic> sources;
  String support(String name) {
    final source = sources[name.contains('.') ? 'public' : 'message'];
    if (source is! Map ||
        !const ['confirmed', 'stale'].contains(source['status'])) {
      return 'unknown';
    }
    final capabilities = source['capabilities'];
    return capabilities is Map && capabilities[name] is Map
        ? capabilities[name]['support'] as String? ?? 'unknown'
        : 'unknown';
  }

  bool supports(String name) => support(name) == 'supported';
  int boundedPositiveLimit(String name, String key, int clientLimit) {
    if (!supports(name)) return clientLimit;
    final source = sources[name.contains('.') ? 'public' : 'message'] as Map;
    final limits = (source['capabilities'] as Map)[name]['limits'];
    final raw = limits is Map ? limits[key] : null;
    final value = raw is int
        ? raw
        : raw is String
        ? int.tryParse(raw)
        : null;
    return value != null && value > 0 && value < clientLimit
        ? value
        : clientLimit;
  }

  bool get stale => sources.values.any(
    (source) => source is Map && source['status'] == 'stale',
  );
}

// A new tenant or session observes a different provider, never the previous
// AsyncValue's retained data. Refreshes within that exact context retain layout.
final _featuresForContextProvider = FutureProvider.autoDispose
    .family<BackendFeatures, (BackendCapabilitiesPort, int)>((
      ref,
      context,
    ) async {
      final timer = Timer(const Duration(minutes: 5), ref.invalidateSelf);
      ref.onDispose(timer.cancel);
      return BackendFeatures(await context.$1.backendCapabilities());
    });
final backendFeaturesProvider = Provider<AsyncValue<BackendFeatures>>((ref) {
  final generation = ref.watch(
    sessionProvider.select((state) => state.generation),
  );
  final identities = ref.watch(identityCorePortProvider);
  if (identities is! BackendCapabilitiesPort) {
    return const AsyncData(BackendFeatures({}));
  }
  return ref.watch(
    _featuresForContextProvider((
      identities as BackendCapabilitiesPort,
      generation,
    )),
  );
});
final backendFeaturesFutureProvider = Provider<Future<BackendFeatures>>((ref) {
  final generation = ref.watch(
    sessionProvider.select((state) => state.generation),
  );
  final identities = ref.watch(identityCorePortProvider);
  if (identities is! BackendCapabilitiesPort) {
    return Future.value(const BackendFeatures({}));
  }
  return ref.watch(
    _featuresForContextProvider((
      identities as BackendCapabilitiesPort,
      generation,
    )).future,
  );
});
Future<void> refreshBackendFeatures(WidgetRef ref) async {
  final identities = ref.read(identityCorePortProvider);
  if (identities is BackendCapabilitiesPort) {
    final generation = ref.read(sessionProvider).generation;
    await (identities as BackendCapabilitiesPort).backendCapabilities(
      force: true,
    );
    if (!ref.context.mounted ||
        ref.read(identityCorePortProvider) != identities ||
        ref.read(sessionProvider).generation != generation) {
      return;
    }
    ref.invalidate(
      _featuresForContextProvider((
        identities as BackendCapabilitiesPort,
        ref.read(sessionProvider).generation,
      )),
    );
  }
}
