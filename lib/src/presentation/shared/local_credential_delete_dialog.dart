import 'package:flutter/cupertino.dart';

import '../../domain/entities/session_identity.dart';
import '../../l10n/l10n.dart';
import 'app_dialog.dart';

class LocalCredentialDeleteDialog extends StatelessWidget {
  const LocalCredentialDeleteDialog({
    super.key,
    required this.identity,
    required this.signsOut,
    required this.onConfirm,
  });

  final SessionIdentity identity;
  final bool signsOut;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final identityLabel = _identityLabel(identity);
    return AppConfirmationDialog(
      title: signsOut
          ? context.l10n.settingsDeleteCredentialConfirmTitle
          : context.l10n.localCredentialDeleteConfirmTitle,
      message: signsOut
          ? context.l10n.settingsDeleteCredentialConfirmContent(identityLabel)
          : context.l10n.localCredentialDeleteConfirmContent(identityLabel),
      helperMessage: signsOut
          ? context.l10n.settingsDeleteCredentialConfirmHint
          : context.l10n.localCredentialDeleteConfirmHint,
      compactTitleTextAlign: TextAlign.center,
      compactMessageTextAlign: TextAlign.center,
      compactHorizontalPadding: 24,
      compactSpacious: true,
      confirmLabel: signsOut
          ? context.l10n.settingsDeleteCredentialConfirmAction
          : context.l10n.localCredentialDeleteAction,
      confirmButtonKey: Key(
        'local-credential-delete-confirm:${identity.localIdentitySelector}',
      ),
      destructive: true,
      onConfirm: onConfirm,
    );
  }
}

String _identityLabel(SessionIdentity identity) {
  final displayName = identity.visibleDisplayName;
  final handle = identity.handle?.trim();
  if (handle != null && handle.isNotEmpty) {
    final normalizedHandle = handle.startsWith('@') ? handle : '@$handle';
    if (displayName.isNotEmpty && displayName != handle) {
      return '$displayName ($normalizedHandle)';
    }
    return normalizedHandle;
  }
  return displayName;
}
