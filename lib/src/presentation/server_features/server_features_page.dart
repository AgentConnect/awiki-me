import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../app/app_services.dart';
import '../../application/tenant/app_tenant.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/session_provider.dart';
import '../settings/settings_detail_layout.dart';
import '../shared/awiki_me_design.dart';
import '../shared/widgets/awiki_glass.dart';
import 'backend_capabilities_provider.dart';

class ServerFeaturesPage extends ConsumerStatefulWidget {
  const ServerFeaturesPage({super.key, this.embedded = false});
  final bool embedded;
  @override
  ConsumerState<ServerFeaturesPage> createState() => _ServerFeaturesPageState();
}

class _ServerFeaturesPageState extends ConsumerState<ServerFeaturesPage> {
  bool _refreshing = false;
  bool _failed = false;
  Object? _context;
  int _request = 0;

  Future<void> _refresh() async {
    if (_refreshing) return;
    final request = ++_request;
    setState(() {
      _refreshing = true;
      _failed = false;
    });
    try {
      await refreshBackendFeatures(ref);
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    } finally {
      if (mounted && request == _request) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = context.awikiTheme;
    final tenant = ref.watch(activeAppTenantProvider);
    final state = ref.watch(backendFeaturesProvider);
    final generation = ref.watch(sessionProvider.select((s) => s.generation));
    final stamp = (tenant.id, generation, ref.watch(identityCorePortProvider));
    if (_context != stamp) {
      _context = stamp;
      _request++;
      _refreshing = false;
      _failed = false;
    }
    final features = state.valueOrNull ?? const BackendFeatures({});
    final groups = [
      (
        'message',
        l.serverFeaturesMessageSource,
        [
          (
            'direct',
            l.serverFeaturesMessaging,
            l.serverFeaturesMessagingDescription,
            CupertinoIcons.chat_bubble,
          ),
          (
            'groups',
            l.serverFeaturesGroups,
            l.serverFeaturesGroupsDescription,
            CupertinoIcons.person_2,
          ),
          (
            'attachments',
            l.serverFeaturesAttachments,
            l.serverFeaturesAttachmentsDescription,
            CupertinoIcons.paperclip,
          ),
          (
            'direct_e2ee',
            l.serverFeaturesEncryption,
            l.serverFeaturesEncryptionDescription,
            CupertinoIcons.lock,
          ),
          (
            'group_e2ee',
            l.serverFeaturesGroupEncryption,
            l.serverFeaturesGroupEncryptionDescription,
            CupertinoIcons.lock_shield,
          ),
        ],
      ),
      (
        'public',
        l.serverFeaturesAccountSource,
        [
          (
            'identity.multi_device',
            l.serverFeaturesDevices,
            l.serverFeaturesDevicesDescription,
            CupertinoIcons.device_phone_portrait,
          ),
          (
            'agents.managed_agents',
            l.serverFeaturesAgents,
            l.serverFeaturesAgentsDescription,
            CupertinoIcons.sparkles,
          ),
          (
            'services.mail',
            l.serverFeaturesMail,
            l.serverFeaturesMailDescription,
            CupertinoIcons.envelope,
          ),
          (
            'content.pages',
            l.serverFeaturesPages,
            l.serverFeaturesPagesDescription,
            CupertinoIcons.doc_text,
          ),
          (
            'client_updates.policy',
            l.serverFeaturesUpdates,
            l.serverFeaturesUpdatesDescription,
            CupertinoIcons.arrow_down_circle,
          ),
        ],
      ),
    ];
    return SettingsDetailLayout(
      title: l.serverFeaturesTitle,
      embedded: widget.embedded,
      maxWidth: 1040,
      trailing: CupertinoButton(
        key: const Key('server-features-refresh'),
        padding: EdgeInsets.zero,
        onPressed: _refreshing ? null : _refresh,
        child: _refreshing
            ? Semantics(
                label: l.serverFeaturesConfirming,
                child: const CupertinoActivityIndicator(),
              )
            : Icon(CupertinoIcons.refresh, semanticLabel: l.commonRefresh),
      ),
      children: [
        Text(tenant.name, style: theme.sectionTitle),
        const SizedBox(height: 4),
        Text(
          Uri.tryParse(tenant.backendBaseUrl)?.host ?? '',
          style: theme.cardSubtitle,
        ),
        const SizedBox(height: 12),
        Text(l.serverFeaturesIntro, style: theme.cardSubtitle),
        const SizedBox(height: 4),
        Text(l.serverFeaturesAvailabilityNote, style: theme.cardSubtitle),
        if (state.isLoading && state.valueOrNull == null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(l.serverFeaturesConfirming, style: theme.cardSubtitle),
          ),
        if (_failed || state.hasError)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              l.serverFeaturesRefreshFailed,
              style: TextStyle(color: theme.danger),
            ),
          ),
        for (final group in groups) ...[
          const SizedBox(height: 24),
          Text(group.$2, style: theme.sectionTitle),
          const SizedBox(height: 6),
          ..._sourceNotes(context, features.sources[group.$1]),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = math.max(
                1.0,
                MediaQuery.textScalerOf(context).scale(14) / 14,
              );
              final columns = ((constraints.maxWidth + 12) / (240 * scale + 12))
                  .floor()
                  .clamp(1, 3);
              return Column(
                key: Key('server-feature-grid-${group.$1}-$columns'),
                children: [
                  for (var start = 0; start < group.$3.length; start += columns)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var col = 0; col < columns; col++) ...[
                              if (col > 0) const SizedBox(width: 12),
                              Expanded(
                                child: start + col < group.$3.length
                                    ? _card(
                                        context,
                                        group.$3[start + col],
                                        features,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  List<Widget> _sourceNotes(BuildContext context, dynamic source) {
    final l = context.l10n;
    final theme = context.awikiTheme;
    final notes = <String>[];
    if (source is Map) {
      final timestamp = source['fetched_at'];
      if (timestamp is int && timestamp >= 0 && timestamp <= 8640000000000) {
        final date = DateTime.fromMillisecondsSinceEpoch(
          timestamp * 1000,
        ).toLocal();
        notes.add(
          l.serverFeaturesUpdatedAt(
            DateFormat.yMd(
              Localizations.localeOf(context).toString(),
            ).add_Hm().format(date),
          ),
        );
      }
      if (source['refresh_error'] == 'upgrade_required' ||
          source['status'] == 'incompatible') {
        notes.add(l.serverFeaturesUpgradeRequired);
      } else if (source['status'] == 'stale') {
        notes.add(l.serverFeaturesStale);
      } else if (source['status'] == 'unavailable') {
        notes.add(l.serverFeaturesRefreshFailed);
      }
    }
    return [for (final note in notes) Text(note, style: theme.cardSubtitle)];
  }

  Widget _card(
    BuildContext context,
    (String, String, String, IconData) item,
    BackendFeatures features,
  ) {
    final theme = context.awikiTheme;
    final l = context.l10n;
    final support = features.support(item.$1);
    final label = switch (support) {
      'supported' => l.serverFeaturesStatusSupported,
      'unsupported' => l.serverFeaturesStatusUnsupported,
      _ => l.serverFeaturesStatusUnknown,
    };
    return DecoratedBox(
      key: ValueKey('server-feature-${item.$1}'),
      decoration: awikiGroupDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(item.$4, size: 18, color: theme.secondaryText),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.$2,
                    style: TextStyle(
                      color: theme.title,
                      fontSize: widget.embedded ? 14 : 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                item.$3,
                style: TextStyle(
                  color: theme.secondaryText,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    support == 'supported'
                        ? CupertinoIcons.checkmark_circle
                        : support == 'unsupported'
                        ? CupertinoIcons.minus_circle
                        : CupertinoIcons.clock,
                    size: 15,
                    color: support == 'supported'
                        ? AwikiMePalette.successGreen
                        : theme.secondaryText,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(color: theme.secondaryText, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
