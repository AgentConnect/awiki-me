import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../l10n/l10n.dart';
import '../shared/app_dialog.dart';
import '../shared/avatar_badge.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/identity_profile_surface.dart';
import '../shared/responsive_layout.dart';
import '../shared/sidebar_workspace.dart';
import 'profile_page.dart';
import 'profile_provider.dart';

Future<void> showCurrentIdentityDialog(BuildContext context) {
  return AppNavigator.showDialog<void>(
    context,
    (dialogContext) => AppDialogScaffold(
      key: const Key('desktop-current-identity-dialog'),
      maxWidth: IdentityProfileLayout.dialogMaxWidth,
      maxHeightFraction: 0.88,
      borderRadius: BorderRadius.circular(
        IdentityProfileLayout.dialogRadius(dialogContext),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 4),
            child: AppDialogHeader(
              title: dialogContext.l10n.profileMeTitle,
              closeButtonKey: const Key('desktop-current-identity-close'),
              onClose: () => Navigator.of(dialogContext).pop(),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.72,
            ),
            child: const ProfilePage(
              embedded: true,
              showTitle: false,
              shrinkWrap: true,
              bottomInset: 20,
            ),
          ),
        ],
      ),
    ),
  );
}

class ProfileWorkspacePage extends StatelessWidget {
  const ProfileWorkspacePage({super.key, this.listFooter, this.onCompactBack});

  final Widget? listFooter;
  final VoidCallback? onCompactBack;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    if (!responsive.supportsTwoPane) {
      return ProfilePage(onBack: onCompactBack);
    }

    return AwikiSidebarWorkspace(
      footer: listFooter,
      sidebar: _ProfileSidebar(bottomInset: listFooter == null ? 24 : 16),
      detailPane: DecoratedBox(
        decoration: BoxDecoration(color: context.awikiTheme.background),
        child: const SafeArea(
          bottom: false,
          child: ProfilePage(embedded: true, bottomInset: 24, showTitle: false),
        ),
      ),
    );
  }
}

class _ProfileSidebar extends ConsumerWidget {
  const _ProfileSidebar({required this.bottomInset});

  final double bottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).profile;
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return AwikiMeShellTabPage(
      title: context.l10n.profileMeTitle,
      child: profile == null
          ? const Center(child: CupertinoActivityIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(
                responsive.spacing(16),
                responsive.spacing(12),
                responsive.spacing(16),
                bottomInset,
              ),
              children: <Widget>[
                Container(
                  key: const Key('profile-sidebar-summary'),
                  padding: EdgeInsets.all(responsive.spacing(14)),
                  decoration: BoxDecoration(
                    color: theme.subtleSurface,
                    borderRadius: BorderRadius.circular(
                      responsive.displayScaled(AwikiMeRadii.md),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      AvatarBadge(
                        seed: DidDisplayFormatter.profileHandleLabel(profile),
                        size: 48,
                        avatarUri: profile.avatarUri,
                      ),
                      SizedBox(height: responsive.spacing(12)),
                      Text(
                        DidDisplayFormatter.profileName(profile),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.title,
                          fontSize: responsive.titleLg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: responsive.spacing(4)),
                      Text(
                        DidDisplayFormatter.profileHandleLabel(profile),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.secondaryText,
                          fontSize: responsive.bodySm,
                        ),
                      ),
                      SizedBox(height: responsive.spacing(8)),
                      Text(
                        DidDisplayFormatter.compactDidPath(profile.did),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.tertiaryText,
                          fontSize: responsive.metaSm,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
