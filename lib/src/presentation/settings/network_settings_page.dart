import 'dart:async';
import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/desktop_network_preference.dart';
import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/widgets/awiki_glass.dart';
import 'settings_detail_layout.dart';

final desktopNetworkPreferenceProvider = Provider<DesktopNetworkPreference>(
  (ref) => DesktopNetworkPreference.instance,
);

class NetworkSettingsPage extends ConsumerStatefulWidget {
  const NetworkSettingsPage({super.key, this.embedded = false});
  final bool embedded;
  @override
  ConsumerState<NetworkSettingsPage> createState() =>
      _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends ConsumerState<NetworkSettingsPage> {
  Timer? _timer;
  late DesktopNetworkPreference _preference;
  bool _initializing = true;
  bool _ready = false;
  bool _initializeFailed = false;
  bool _saveFailed = false;
  bool _reading = false;
  bool _hasStatus = false;
  bool _statusFailed = false;

  @override
  void initState() {
    super.initState();
    _preference = ref.read(desktopNetworkPreferenceProvider)
      ..addListener(_changed);
    unawaited(_initialize());
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_ready) unawaited(_refresh());
    });
  }

  Future<void> _initialize() async {
    setState(() {
      _initializing = true;
      _initializeFailed = false;
    });
    try {
      await _preference.initialize();
      if (!mounted) return;
      setState(() {
        _ready = true;
        _initializing = false;
      });
      await _refresh();
    } catch (_) {
      if (mounted) setState(() => _initializeFailed = true);
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  Future<void> _refresh() async {
    if (_reading || !mounted) return;
    setState(() => _reading = true);
    try {
      await _preference.refreshStatus();
      if (mounted) {
        setState(() {
          _hasStatus = true;
          _statusFailed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _statusFailed = true);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _set(bool value) async {
    try {
      await _preference.setEnabled(value);
      if (!mounted) return;
      setState(() => _saveFailed = false);
      await _refresh();
    } catch (_) {
      if (mounted) setState(() => _saveFailed = true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _preference.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = context.awikiTheme;
    final status = switch (_preference.status) {
      core.AwikiNetworkStatus.systemProxy => l.settingsNetworkSystemProxy,
      core.AwikiNetworkStatus.direct => l.settingsNetworkDirect,
      core.AwikiNetworkStatus.proxyFallback => l.settingsNetworkFallback,
    };
    Widget group(List<Widget> children) => DecoratedBox(
      decoration: awikiGroupDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
    Widget retry(Future<void> Function()? action) => Align(
      alignment: Alignment.centerLeft,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 8),
        onPressed: action,
        child: Text(l.commonRetry),
      ),
    );
    return SettingsDetailLayout(
      key: const Key('network-settings-page'),
      title: l.settingsNetwork,
      embedded: widget.embedded,
      children: [
        group([
          Row(
            children: [
              Expanded(
                child: Text(
                  l.settingsUseSystemProxy,
                  style: TextStyle(
                    color: theme.title,
                    fontSize: widget.embedded ? 14 : 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              CupertinoSwitch(
                key: const Key('use-system-proxy-switch'),
                value: _preference.enabled,
                onChanged: !_ready || _initializing || _preference.saving
                    ? null
                    : _set,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(l.settingsSystemProxyDescription, style: theme.cardSubtitle),
          if (_initializing)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: CupertinoActivityIndicator(),
              ),
            ),
          if (_initializeFailed) ...[
            const SizedBox(height: 12),
            Text(
              l.settingsNetworkInitializeFailed,
              style: TextStyle(color: theme.danger),
            ),
            retry(_initialize),
          ],
          if (_saveFailed) ...[
            const SizedBox(height: 12),
            Text(
              l.settingsNetworkSaveFailed,
              style: TextStyle(color: theme.danger),
            ),
          ],
        ]),
        const SizedBox(height: 24),
        Text(l.settingsNetworkRecentPath, style: theme.cardSubtitle),
        const SizedBox(height: 8),
        group([
          Text(
            _hasStatus
                ? status
                : _statusFailed || _initializeFailed
                ? l.settingsNetworkStatusFailed
                : l.settingsNetworkReading,
            key: const Key('network-status'),
            style: TextStyle(
              color: theme.title,
              fontSize: widget.embedded ? 14 : 16,
            ),
          ),
          if (_hasStatus && _statusFailed) ...[
            const SizedBox(height: 8),
            Text(l.settingsNetworkStatusFailed, style: theme.cardSubtitle),
          ],
          if (_statusFailed) retry(_reading ? null : _refresh),
        ]),
      ],
    );
  }
}
