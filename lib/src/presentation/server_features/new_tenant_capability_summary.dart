import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/tenant/app_tenant.dart';
import '../../l10n/l10n.dart';
import 'backend_capabilities_provider.dart';

/// A one-time, nonmodal summary for newly added tenants. Existing profiles
/// default to seen, so upgrading never restarts the add-tenant experience.
class NewTenantCapabilitySummary extends ConsumerStatefulWidget {
  const NewTenantCapabilitySummary({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<NewTenantCapabilitySummary> createState() => _SummaryState();
}

class _SummaryState extends ConsumerState<NewTenantCapabilitySummary> {
  String? _shownTenant;
  Timer? _timer;
  bool _visible = false;
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(activeAppTenantProvider);
    final features = ref.watch(backendFeaturesProvider).valueOrNull;
    final source = features?.sources['public'];
    if (tenant.capabilitySummaryPending &&
        _shownTenant != tenant.id &&
        source is Map &&
        const ['confirmed', 'stale'].contains(source['status'])) {
      _shownTenant = tenant.id;
      _visible = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final actions = ref.read(appTenantActionsProvider);
        if (actions is TenantCapabilitySummaryActions) {
          unawaited(
            (actions as TenantCapabilitySummaryActions)
                .markCapabilitySummarySeen(tenant.id)
                .catchError((Object _) {
                  // A concurrent tenant edit may win the registry CAS. Retry next entry.
                }),
          );
        }
      });
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 7), () {
        if (mounted) setState(() => _visible = false);
      });
    }
    final l10n = context.l10n;
    String status(String name) => switch (features?.support(name)) {
      'supported' => l10n.serverFeaturesSupported,
      'unsupported' => l10n.serverFeaturesUnsupported,
      _ => l10n.serverFeaturesUnknown,
    };
    return Stack(
      children: [
        widget.child,
        if (_visible && _shownTenant == tenant.id)
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    key: const Key('new-tenant-capability-summary'),
                    constraints: const BoxConstraints(maxWidth: 480),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: CupertinoColors.secondarySystemBackground
                          .resolveFrom(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${l10n.serverFeaturesDevices}：${status('identity.multi_device')} · ${l10n.serverFeaturesAgents}：${status('agents.managed_agents')}\n${l10n.serverFeaturesSummaryDetail}',
                      style: const TextStyle(fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
