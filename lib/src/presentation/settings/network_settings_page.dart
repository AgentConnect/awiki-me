import '../shared/widgets/awiki_glass.dart';
import 'dart:async';
import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/desktop_network_preference.dart';
import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/widgets/app_widgets.dart';

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
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _preference = ref.read(desktopNetworkPreferenceProvider)
      ..addListener(_changed);
    unawaited(_initialize());
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  Future<void> _initialize() async {
    try {
      await _preference.initialize();
      await _refresh();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _refresh() async {
    try {
      await _preference.refreshStatus();
    } catch (_) {
      /* Next tick retries diagnostics. */
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _set(bool value) async {
    try {
      await _preference.setEnabled(value);
      if (mounted) setState(() => _failed = false);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
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
    final l10n = context.l10n;
    final theme = context.awikiTheme;
    final status = switch (_preference.status) {
      core.AwikiNetworkStatus.systemProxy => l10n.settingsNetworkSystemProxy,
      core.AwikiNetworkStatus.direct => l10n.settingsNetworkDirect,
      core.AwikiNetworkStatus.proxyFallback => l10n.settingsNetworkFallback,
    };
    return CupertinoPageScaffold(
      key: const Key('network-settings-page'),
      backgroundColor: theme.background,
      child: SafeArea(
        child: Column(
          children: [
            AwikiMeTopBar(
              title: l10n.settingsNetwork,
              leading: widget.embedded
                  ? const SizedBox.shrink()
                  : AwikiBackButton(
                      onTap: () => Navigator.of(context).pop(),
                      semanticsLabel: l10n.commonBack,
                    ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: widget.embedded ? 460 : 560,
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      AppListTile(
                        title: l10n.settingsUseSystemProxy,
                        trailing: CupertinoSwitch(
                          key: const Key('use-system-proxy-switch'),
                          value: _preference.enabled,
                          onChanged: _preference.saving ? null : _set,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.settingsSystemProxyDescription,
                        style: TextStyle(
                          color: theme.secondaryText,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        status,
                        key: const Key('network-status'),
                        style: TextStyle(
                          color: theme.secondaryText,
                          fontSize: 13,
                        ),
                      ),
                      if (_failed)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(l10n.settingsNetworkSaveFailed),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
