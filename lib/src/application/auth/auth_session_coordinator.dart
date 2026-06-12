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

  Future<AppSession?>? _refreshInFlight;

  Future<String> ensureBearerToken({bool forceRefresh = false}) async {
    var session = await _sessions.currentSession();
    if (session == null) {
      throw const AuthSessionUnavailable('当前登录状态不可用。');
    }
    if (forceRefresh || !_hasUsableToken(session)) {
      session = await _refreshSession();
    }
    final token = session?.jwtToken?.trim();
    if (session == null || token == null || token.isEmpty) {
      throw const AuthSessionUnavailable('登录状态已失效，请重新登录。');
    }
    return token;
  }

  Future<AppSession?> _refreshSession() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final future = _sessions.refreshSession().then((session) {
      if (session != null) {
        _onSessionUpdated?.call(session);
      }
      return session;
    });
    _refreshInFlight = future;
    return future.whenComplete(() {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    });
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
