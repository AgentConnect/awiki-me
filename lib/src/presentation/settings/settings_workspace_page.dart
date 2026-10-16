import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_shell/providers/session_provider.dart';
import '../devices/devices_page.dart';
import '../shared/sidebar_workspace.dart';
import 'display_settings_page.dart';
import 'language_selection_page.dart';
import 'settings_page.dart';
import '../server_features/server_features_page.dart';

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
    final content = switch (_selected) {
      SettingsDetail.serverFeatures => const ServerFeaturesPage(embedded: true),
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
        // Dispose device subroutes when switching categories or identities.
        // Recovery is hosted by the root navigator across session replacement.
        child: Navigator(
          key: ValueKey((sessionState.activeEpoch, _selected)),
          pages: [
            CupertinoPage<void>(key: ValueKey(_selected), child: content),
          ],
          onDidRemovePage: (_) {},
        ),
      ),
    );
  }
}
