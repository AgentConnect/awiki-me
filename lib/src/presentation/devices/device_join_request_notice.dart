import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_time_formatter.dart';
import '../../domain/entities/device_management.dart';
import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/widgets/app_widgets.dart';
import '../shared/widgets/awiki_glass.dart';
import 'device_join_approval_sheet.dart';
import 'devices_provider.dart';

/// The pending join request a managing device should review, if any.
final pendingJoinRequestProvider = Provider<DeviceJoinRequestNotice?>((ref) {
  return ref.watch(
    devicesProvider.select((state) {
      if (!state.currentDeviceCanManage) {
        return null;
      }
      final requests = state.visibleJoinRequests;
      return requests.isEmpty ? null : requests.first;
    }),
  );
});

/// Opens the approval for [request] and refreshes the typed inbox afterwards.
Future<void> reviewDeviceJoinRequest(
  BuildContext context,
  WidgetRef ref,
  DeviceJoinRequestNotice request,
) async {
  await showDeviceJoinApproval(context, request);
  if (context.mounted) {
    await ref.read(devicesProvider.notifier).refreshJoinInbox();
  }
}

/// Glass notice for a new device asking to join: the device, how long the
/// request stays valid, and a soft brand "review" pill.
class DeviceJoinRequestNoticeCard extends StatelessWidget {
  const DeviceJoinRequestNoticeCard({
    super.key,
    required this.request,
    required this.onReview,
    this.floating = false,
  });

  final DeviceJoinRequestNotice request;
  final VoidCallback onReview;

  /// Floating copies sit over other content and get a thicker fill and shadow.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final l10n = context.l10n;
    final card = AwikiGlassSurface(
      borderRadius: BorderRadius.circular(18),
      child: ColoredBox(
        color: floating
            ? theme.surface.withValues(alpha: 0.6)
            : const Color(0x00000000),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: <Widget>[
              Icon(CupertinoIcons.device_laptop, color: theme.title, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      l10n.deviceJoinNoticeTitle(request.protocolDeviceId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.title,
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.deviceJoinNoticeExpiry(
                        DateTimeFormatter.requestTime(
                          request.expiresAt.toLocal(),
                        ),
                      ),
                      maxLines: 1,
                      style: TextStyle(
                        color: theme.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.primarySoft,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.primary.withValues(alpha: 0.22),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  l10n.deviceReviewAction,
                  style: TextStyle(
                    color: theme.primaryDeep,
                    fontSize: 13,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      identifier: 'device-join-request-entry',
      button: true,
      child: AppPressable(
        key: const Key('device-join-request-banner'),
        onTap: onReview,
        semanticLabel: l10n.deviceJoinApprovalTitle,
        scaleOnPress: true,
        pressedScale: 0.98,
        borderRadius: BorderRadius.circular(18),
        child: floating
            ? DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: theme.overlayShadow,
                ),
                child: card,
              )
            : card,
      ),
    );
  }
}
