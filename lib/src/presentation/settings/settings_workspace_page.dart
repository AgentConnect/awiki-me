import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_shell/providers/session_provider.dart';
import '../devices/devices_page.dart';
import '../recovery/handle_recovery_page.dart';
import '../shared/sidebar_workspace.dart';
import 'display_settings_page.dart';
import 'language_selection_page.dart';
import 'settings_page.dart';

/// Desktop settings keep navigation and the active controls visible together.
class SettingsWorkspacePage extends ConsumerStatefulWidget {
  const SettingsWorkspacePage({super.key});

  @override
  ConsumerState<SettingsWorkspacePage> createState() =>
      _SettingsWorkspacePageState();
}

class _SettingsWorkspacePageState extends ConsumerState<SettingsWorkspacePage> {
  SettingsDetail _selected = SettingsDetail.display;

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(sessionProvider);
    final identity = sessionState.session;
    final recovering =
        _selected == SettingsDetail.recovery &&
        identity?.handle?.trim().isNotEmpty == true &&
        identity?.localIdentityId?.trim().isNotEmpty == true;
    final root = _selected == SettingsDetail.recovery
        ? SettingsDetail.display
        : _selected;
    final content = switch (root) {
      SettingsDetail.devices => const DevicesPage(embedded: true),
      SettingsDetail.language => const LanguageSelectionPage(embedded: true),
      _ => const DisplaySettingsPage(embedded: true),
    };
    return AwikiSidebarWorkspace(
      sidebar: SizedBox.expand(
        key: const Key('mac-settings-list-pane'),
        child: SettingsPage(
          embedded: true,
          selectedDetail: _selected,
          onDetailSelected: (detail) => setState(() => _selected = detail),
        ),
      ),
      detailPane: SizedBox.expand(
        key: const Key('settings-detail-pane'),
        // Dispose nested device routes and owner-bound recovery state when
        // switching categories or identities; never push over the App shell.
        child: Navigator(
          key: ValueKey((sessionState.activeEpoch, root)),
          pages: [
            CupertinoPage<void>(key: ValueKey(root), child: content),
            if (recovering)
              CupertinoPage<void>(
                key: const ValueKey(SettingsDetail.recovery),
                child: HandleRecoveryPage(
                  startNew: true,
                  initialHandle: identity!.handle!.trim(),
                  initialPhone: '',
                  autoRequestOtp: false,
                  localIdentityId: identity.localIdentityId!.trim(),
                  allowPhoneInput: true,
                ),
              ),
          ],
          onDidRemovePage: (page) {
            if (page.key == const ValueKey(SettingsDetail.recovery) &&
                _selected == SettingsDetail.recovery &&
                mounted) {
              setState(() => _selected = SettingsDetail.display);
            }
          },
        ),
      ),
    );
  }
}
