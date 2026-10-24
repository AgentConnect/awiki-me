import 'desktop_network_setup_stub.dart'
    if (dart.library.io) 'desktop_network_setup_io.dart';
import 'dart:async';
import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:flutter/foundation.dart';
import 'app_key_value_store.dart';

/// Application-local preference, deliberately outside account and tenant stores.
class DesktopNetworkPreference extends ChangeNotifier {
  DesktopNetworkPreference({
    Future<AppKeyValueStore> Function()? preferences,
    Future<void> Function(bool)? apply,
    Future<core.AwikiNetworkStatus> Function()? readStatus,
  }) : _readStatus = readStatus ?? core.AwikiDesktopNetwork.status,
       _preferences =
           preferences ??
           (() => FileAppKeyValueStore.create(
             fileName: 'awiki_me_network_preferences.json',
           )),
       _apply =
           apply ??
           ((enabled) async => core.AwikiDesktopNetwork.configure(
             enabled
                 ? core.AwikiNetworkPolicy.systemPreferred
                 : core.AwikiNetworkPolicy.direct,
             caBundle: await desktopNetworkCaBundle(),
           ));
  static const key = 'app.network.use_system_proxy.v1';
  static final instance = DesktopNetworkPreference();
  final Future<AppKeyValueStore> Function() _preferences;
  final Future<void> Function(bool) _apply;
  final Future<core.AwikiNetworkStatus> Function() _readStatus;
  Future<void>? _initializing;
  Future<void> _writes = Future.value();
  bool enabled = true;
  bool saving = false;
  core.AwikiNetworkStatus status = core.AwikiNetworkStatus.direct;
  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    final preferences = await _preferences();
    enabled = (await preferences.read(key: key)) != 'false';
    await _apply(enabled);
    notifyListeners();
  }

  Future<void> setEnabled(bool value) {
    final operation = _writes.then((_) async {
      await initialize();
      saving = true;
      notifyListeners();
      try {
        await _apply(value);
        try {
          await (await _preferences()).write(key: key, value: value.toString());
        } catch (_) {
          await _apply(enabled);
          rethrow;
        }
        enabled = value;
      } finally {
        saving = false;
        notifyListeners();
      }
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> refreshStatus() async {
    status = await _readStatus();
    notifyListeners();
  }
}

bool get supportsDesktopNetwork =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows);
