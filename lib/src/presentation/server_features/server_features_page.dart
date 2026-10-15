import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/widgets/awiki_glass.dart';
import '../shared/awiki_me_top_bar.dart';
import 'backend_capabilities_provider.dart';

class ServerFeaturesPage extends ConsumerWidget {
  const ServerFeaturesPage({super.key, this.embedded = false});
  final bool embedded;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final features =
        ref.watch(backendFeaturesProvider).valueOrNull ??
        const BackendFeatures({});
    final rows = <String, String>{
      'direct': l10n.serverFeaturesMessaging,
      'groups': l10n.serverFeaturesGroups,
      'attachments': l10n.serverFeaturesAttachments,
      'direct_e2ee': l10n.serverFeaturesEncryption,
      'group_e2ee': l10n.serverFeaturesGroupEncryption,
      'identity.multi_device': l10n.serverFeaturesDevices,
      'agents.managed_agents': l10n.serverFeaturesAgents,
      'services.mail': l10n.serverFeaturesMail,
      'content.pages': l10n.serverFeaturesPages,
      'client_updates.policy': l10n.serverFeaturesUpdates,
    };
    return CupertinoPageScaffold(
      backgroundColor: context.awikiTheme.background,
      child: SafeArea(
        child: Column(
          children: [
            AwikiMeTopBar(
              title: l10n.serverFeaturesTitle,
              leading: embedded
                  ? const SizedBox.shrink()
                  : AwikiBackButton(
                      onTap: () => Navigator.of(context).maybePop(),
                      semanticsLabel: l10n.commonBack,
                    ),
              trailing: CupertinoButton(
                key: const Key('server-features-refresh'),
                padding: EdgeInsets.zero,
                onPressed: () => refreshBackendFeatures(ref),
                child: Icon(
                  CupertinoIcons.refresh,
                  semanticLabel: l10n.commonRefresh,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (features.stale)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(l10n.serverFeaturesStale),
                    ),
                  for (final row in rows.entries)
                    Padding(
                      key: ValueKey('server-feature-${row.key}'),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.value,
                            style: TextStyle(color: context.awikiTheme.title),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            switch (features.support(row.key)) {
                              'supported' => l10n.serverFeaturesSupported,
                              'unsupported' => l10n.serverFeaturesUnsupported,
                              _ => l10n.serverFeaturesUnknown,
                            },
                            style: TextStyle(
                              color: context.awikiTheme.secondaryText,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
