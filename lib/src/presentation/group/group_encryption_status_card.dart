// [INPUT]: A Group DID and redacted group-encryption presentation state.
// [OUTPUT]: Minimal preparing/retry/ready UI with one explicit retry action.
// [POS]: Group detail projection; never displays MLS Leaf identifiers or private state.

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../domain/entities/group_encryption_status.dart';
import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/widgets/app_widgets.dart';
import 'group_encryption_provider.dart';

class GroupEncryptionStatusCard extends ConsumerStatefulWidget {
  const GroupEncryptionStatusCard({super.key, required this.groupDid});

  final String groupDid;

  @override
  ConsumerState<GroupEncryptionStatusCard> createState() =>
      _GroupEncryptionStatusCardState();
}

class _GroupEncryptionStatusCardState
    extends ConsumerState<GroupEncryptionStatusCard> {
  @override
  void initState() {
    super.initState();
    _requestLoad();
  }

  @override
  void didUpdateWidget(covariant GroupEncryptionStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupDid != widget.groupDid) {
      _requestLoad();
    }
  }

  void _requestLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !ref.read(multiDeviceGroupE2eeEnabledProvider)) {
        return;
      }
      ref.read(groupEncryptionProvider(widget.groupDid).notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(multiDeviceGroupE2eeEnabledProvider)) {
      return const SizedBox.shrink();
    }
    final view = ref.watch(groupEncryptionProvider(widget.groupDid));
    final status = view.status;
    final readiness = status?.readiness ?? GroupEncryptionReadiness.preparing;
    final isBusy =
        view.isLoading ||
        view.isRetrying ||
        readiness == GroupEncryptionReadiness.preparing;
    final title = switch (readiness) {
      GroupEncryptionReadiness.preparing =>
        context.l10n.groupEncryptionPreparingTitle,
      GroupEncryptionReadiness.needsRetry =>
        context.l10n.groupEncryptionNeedsRetryTitle,
      GroupEncryptionReadiness.ready => context.l10n.groupEncryptionReadyTitle,
      GroupEncryptionReadiness.unavailable =>
        context.l10n.groupEncryptionUnavailableTitle,
    };
    final detail = switch (readiness) {
      GroupEncryptionReadiness.preparing =>
        context.l10n.groupEncryptionPreparingDetail,
      GroupEncryptionReadiness.needsRetry =>
        context.l10n.groupEncryptionNeedsRetryDetail,
      GroupEncryptionReadiness.ready => context.l10n.groupEncryptionReadyDetail,
      GroupEncryptionReadiness.unavailable =>
        context.l10n.groupEncryptionUnavailableDetail,
    };
    final accent = switch (readiness) {
      GroupEncryptionReadiness.preparing => const Color(0xFF175CD3),
      GroupEncryptionReadiness.needsRetry => const Color(0xFFB54708),
      GroupEncryptionReadiness.ready => const Color(0xFF067647),
      GroupEncryptionReadiness.unavailable => const Color(0xFF667085),
    };
    return AppCardSection(
      key: const Key('group-encryption-status-card'),
      color: accent.withValues(alpha: 0.07),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: isBusy
                ? CupertinoActivityIndicator(color: accent, radius: 10)
                : Icon(
                    CupertinoIcons.lock_shield_fill,
                    color: accent,
                    size: 22,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  key: const Key('group-encryption-status-title'),
                  style: AwikiMeTextStyles.cardTitle.copyWith(color: accent),
                ),
                const SizedBox(height: 4),
                Text(detail, style: AwikiMeTextStyles.cardSubtitle),
              ],
            ),
          ),
          if (readiness == GroupEncryptionReadiness.needsRetry &&
              status?.retryable != false) ...<Widget>[
            const SizedBox(width: 8),
            CupertinoButton(
              key: const Key('group-encryption-retry-button'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(44, 36),
              onPressed: isBusy
                  ? null
                  : () => ref
                        .read(groupEncryptionProvider(widget.groupDid).notifier)
                        .retry(),
              child: Text(context.l10n.groupEncryptionRetry),
            ),
          ],
        ],
      ),
    );
  }
}
