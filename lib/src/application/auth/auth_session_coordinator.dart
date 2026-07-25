import 'dart:async';
import 'dart:convert';

import '../app_session_service.dart';
import '../models/app_session.dart';

typedef AppSessionUpdated = void Function(AppSession session);

class AuthSessionCoordinator {
  AuthSessionCoordinator({
    required AppSessionService sessions,
    AppSessionUpdated? onSessionUpdated,
    DateTime Function()? now,
    this.refreshSkew = const Duration(minutes: 5),
  }) : _sessions = sessions,
       _onSessionUpdated = onSessionUpdated,
       _now = now ?? DateTime.now;

  final AppSessionService _sessions;
  final AppSessionUpdated? _onSessionUpdated;
  final DateTime Function() _now;
  final Duration refreshSkew;

  final Map<AppSessionTransition, Future<AppSession?>> _refreshInFlight =
      <AppSessionTransition, Future<AppSession?>>{};

  Future<String> ensureBearerToken({bool forceRefresh = false}) async {
    return (await ensureBearerSession(forceRefresh: forceRefresh)).bearerToken;
  }

  Future<AuthenticatedBearerSession> ensureBearerSession({
    bool forceRefresh = false,
    AppSessionTransition? expectedTransition,
  }) async {
    var lease = await _sessions.currentSessionLease();
    _requireExpectedTransition(lease, expectedTransition);
    var session = lease?.session;
    if (lease == null || session == null) {
      throw const AuthSessionUnavailable('auth_session_unavailable');
    }
    if (forceRefresh || !_hasUsableToken(session)) {
      session = await _refreshSession(lease);
      final refreshedLease = await _sessions.currentSessionLease();
      if (session == null ||
          refreshedLease == null ||
          !identical(refreshedLease.transition, lease.transition)) {
        throw const AuthSessionUnavailable('auth_session_changed');
      }
      lease = refreshedLease;
    }
    _requireExpectedTransition(lease, expectedTransition);
    final token = session.jwtToken?.trim();
    if (token == null || token.isEmpty) {
      throw const AuthSessionUnavailable('session_expired');
    }
    return AuthenticatedBearerSession(
      transition: lease.transition,
      bearerToken: token,
    );
  }

  Future<AppSession?> _refreshSession(AppSessionLease lease) {
    final inFlight = _refreshInFlight[lease.transition];
    if (inFlight != null) {
      return inFlight;
    }
    late final Future<AppSession?> future;
    future = _sessions.refreshSession().then((session) async {
      final currentLease = await _sessions.currentSessionLease();
      if (session == null ||
          currentLease == null ||
          !identical(currentLease.transition, lease.transition)) {
        return null;
      }
      _onSessionUpdated?.call(session);
      return session;
    });
    _refreshInFlight[lease.transition] = future;
    return future.whenComplete(() {
      if (identical(_refreshInFlight[lease.transition], future)) {
        _refreshInFlight.remove(lease.transition);
      }
    });
  }

  void _requireExpectedTransition(
    AppSessionLease? lease,
    AppSessionTransition? expected,
  ) {
    if (expected != null &&
        (lease == null || !identical(lease.transition, expected))) {
      throw const AuthSessionUnavailable('auth_session_changed');
    }
  }

  bool _hasUsableToken(AppSession session) {
    final token = session.jwtToken?.trim();
    if (token == null || token.isEmpty) {
      return false;
    }
    final expiresAt = session.expiresAt ?? _jwtExpiresAt(token);
    if (expiresAt == null) {
      return true;
    }
    return expiresAt.toUtc().isAfter(_now().toUtc().add(refreshSkew));
  }
}

final class AuthenticatedBearerSession {
  const AuthenticatedBearerSession({
    required this.transition,
    required this.bearerToken,
  });

  final AppSessionTransition transition;
  final String bearerToken;
}

class AuthSessionUnavailable implements Exception {
  const AuthSessionUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

DateTime? _jwtExpiresAt(String token) {
  final segments = token.split('.');
  if (segments.length < 2) {
    return null;
  }
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
    );
    if (payload is! Map) {
      return null;
    }
    final exp = payload['exp'];
    if (exp is int) {
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    }
    if (exp is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        (exp * 1000).round(),
        isUtc: true,
      );
    }
    if (exp is String) {
      final seconds = int.tryParse(exp);
      if (seconds != null) {
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}
