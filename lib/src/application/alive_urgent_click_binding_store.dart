import 'dart:async';

import 'ports/remote_push_sync_port.dart';

/// One process-memory bridge from a Core-committed urgent message to its
/// canonical conversation. Native click payloads never carry this route.
///
/// The bridge is deliberately single-entry because Android owns at most one
/// alive-background urgent surface. It is session-fenced, expiry-bounded, and
/// cannot survive process death.
final class AliveUrgentClickBindingStore {
  AliveUrgentClickBindingStore({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  _AliveUrgentClickBinding? _binding;
  Timer? _expiryTimer;

  void bind({
    required RemotePushSessionContext context,
    required String opaqueMessageReference,
    required String conversationId,
    required int expiresAtEpochSeconds,
  }) {
    if (!_opaqueMessagePattern.hasMatch(opaqueMessageReference)) {
      throw ArgumentError.value(
        opaqueMessageReference,
        'opaqueMessageReference',
      );
    }
    if (conversationId.isEmpty || conversationId.trim() != conversationId) {
      throw ArgumentError.value(conversationId, 'conversationId');
    }
    final nowSeconds = _nowSeconds();
    if (expiresAtEpochSeconds <= nowSeconds) {
      throw ArgumentError.value(
        expiresAtEpochSeconds,
        'expiresAtEpochSeconds',
      );
    }
    _expiryTimer?.cancel();
    final binding = _AliveUrgentClickBinding(
      context: context,
      opaqueMessageReference: opaqueMessageReference,
      conversationId: conversationId,
      expiresAtEpochSeconds: expiresAtEpochSeconds,
    );
    _binding = binding;
    _expiryTimer = Timer(
      Duration(seconds: expiresAtEpochSeconds - nowSeconds),
      () {
        if (identical(_binding, binding)) clear();
      },
    );
  }

  String? consume({
    required RemotePushSessionContext context,
    required String opaqueMessageReference,
    required int expiresAtEpochSeconds,
  }) {
    final binding = _binding;
    if (binding == null) return null;
    if (binding.expiresAtEpochSeconds <= _nowSeconds()) {
      clear();
      return null;
    }
    if (!binding.context.matches(context) ||
        binding.opaqueMessageReference != opaqueMessageReference ||
        binding.expiresAtEpochSeconds != expiresAtEpochSeconds) {
      return null;
    }
    final conversationId = binding.conversationId;
    clear();
    return conversationId;
  }

  void discard({
    required RemotePushSessionContext context,
    required String opaqueMessageReference,
    required int expiresAtEpochSeconds,
  }) {
    consume(
      context: context,
      opaqueMessageReference: opaqueMessageReference,
      expiresAtEpochSeconds: expiresAtEpochSeconds,
    );
  }

  void clearForSession(RemotePushSessionContext context) {
    final binding = _binding;
    if (binding != null && binding.context.matches(context)) clear();
  }

  void clear() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _binding = null;
  }

  void dispose() => clear();

  int _nowSeconds() =>
      _now().toUtc().millisecondsSinceEpoch ~/
      Duration.millisecondsPerSecond;
}

final class _AliveUrgentClickBinding {
  const _AliveUrgentClickBinding({
    required this.context,
    required this.opaqueMessageReference,
    required this.conversationId,
    required this.expiresAtEpochSeconds,
  });

  final RemotePushSessionContext context;
  final String opaqueMessageReference;
  final String conversationId;
  final int expiresAtEpochSeconds;
}

final RegExp _opaqueMessagePattern = RegExp(
  r'^message_[A-Za-z0-9_-]{24}$',
);
