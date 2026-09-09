import 'package:flutter/cupertino.dart';

import '../../domain/entities/session_identity.dart';
import '../../l10n/l10n.dart';
import 'app_dialog.dart';

class LocalCredentialDeleteDialog extends StatefulWidget {
  const LocalCredentialDeleteDialog({
    super.key,
    required this.identity,
    required this.signsOut,
    required this.onConfirm,
    required this.loadRecoveryImpact,
  });

  final SessionIdentity identity;
  final bool signsOut;
  final VoidCallback onConfirm;
  final Future<bool> Function() loadRecoveryImpact;

  @override
  State<LocalCredentialDeleteDialog> createState() =>
      _LocalCredentialDeleteDialogState();
}

class _LocalCredentialDeleteDialogState
    extends State<LocalCredentialDeleteDialog> {
  late Future<bool> _impact;

  @override
  void initState() {
    super.initState();
    _impact = widget.loadRecoveryImpact();
  }

  @override
  Widget build(BuildContext context) {
    final identityLabel = _identityLabel(widget.identity);
    return FutureBuilder<bool>(
      future: _impact,
      builder: (context, snapshot) {
        final loaded =
            snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError;
        final signsOut = widget.signsOut;

        return AppConfirmationDialog(
          title: signsOut
              ? context.l10n.settingsDeleteCredentialConfirmTitle
              : context.l10n.localCredentialDeleteConfirmTitle,
          message: signsOut
              ? context.l10n.settingsDeleteCredentialConfirmContent(
                  identityLabel,
                )
              : context.l10n.localCredentialDeleteConfirmContent(identityLabel),
          helperMessage: signsOut
              ? context.l10n.settingsDeleteCredentialConfirmHint
              : context.l10n.localCredentialDeleteConfirmHint,
          body: snapshot.hasError
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(context.l10n.localCredentialDeleteInspectFailed),
                    CupertinoButton(
                      onPressed: () => setState(() {
                        _impact = widget.loadRecoveryImpact();
                      }),
                      child: Text(context.l10n.commonRetry),
                    ),
                  ],
                )
              : !loaded
              ? const Center(child: CupertinoActivityIndicator())
              : snapshot.data == true
              ? Text(context.l10n.localCredentialDeleteRecoveryHint)
              : null,
          compactTitleTextAlign: TextAlign.center,
          compactMessageTextAlign: TextAlign.center,
          compactHorizontalPadding: 24,
          compactSpacious: true,
          confirmLabel: signsOut
              ? context.l10n.settingsDeleteCredentialConfirmAction
              : context.l10n.localCredentialDeleteAction,
          confirmButtonKey: Key(
            'local-credential-delete-confirm:${widget.identity.localIdentitySelector}',
          ),
          destructive: true,
          onConfirm: loaded ? widget.onConfirm : null,
        );
      },
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
