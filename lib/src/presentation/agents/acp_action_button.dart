part of 'acp_task_status.dart';

/// Keeps the exact command and arguments for an unconfirmed transport retry.
/// Compound surfaces use the callbacks to lock competing actions and edits.
class AcpActionButton extends ConsumerStatefulWidget {
  const AcpActionButton({
    super.key,
    required this.session,
    required this.action,
    required this.values,
    required this.label,
    this.enabled = true,
    this.confirmation,
    this.onDone,
    this.beforeSend,
    this.onBusyChanged,
    this.onUncertain,
    this.primary = false,
    this.child,
  });
  final AcpSession session;
  final String action;
  final Map<String, Object?> values;
  final String label;
  final bool enabled;
  final String? confirmation;
  final VoidCallback? onDone;
  final bool Function()? beforeSend;
  final ValueChanged<bool>? onBusyChanged;
  final ValueChanged<bool>? onUncertain;
  final bool primary;
  final Widget? child;
  @override
  ConsumerState<AcpActionButton> createState() => _AcpActionButtonState();
}

class _AcpActionButtonState extends ConsumerState<AcpActionButton>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => _busy || _signature != null;
  bool _busy = false;
  bool _sending = false;
  String? _error;
  String? _signature;
  String? _commandId;
  Map<String, Object?>? _args;

  String get _currentSignature =>
      jsonEncode([widget.session.key, widget.action, widget.values]);

  Future<void> _send() async {
    if (_busy || !widget.enabled) return;
    if (widget.beforeSend?.call() == false) return;
    final epoch = ref.read(sessionProvider).activeEpoch;
    final signature = _currentSignature;
    setState(() {
      _busy = true;
      _error = null;
    });
    widget.onBusyChanged?.call(true);
    updateKeepAlive();
    try {
      if (widget.confirmation != null) {
        final confirmed = await showCupertinoDialog<bool>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            content: Text(widget.confirmation!),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(acpText(context, '取消', 'Cancel')),
              ),
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(acpText(context, '确认', 'Confirm')),
              ),
            ],
          ),
        );
        if (confirmed != true ||
            !mounted ||
            !widget.enabled ||
            ref.read(sessionProvider).activeEpoch != epoch ||
            signature != _currentSignature) {
          return;
        }
      }
      if (signature != _signature) {
        _signature = signature;
        _commandId = newAcpCommandId();
        _args = acpCommandArgs(
          widget.session,
          widget.action,
          values: widget.values,
        );
      }
      setState(() => _sending = true);
      await ref
          .read(acpControlServiceProvider)
          .send(
            agentDid: widget.session.agentDid,
            commandId: _commandId!,
            args: _args!,
          );
      if (!mounted || ref.read(sessionProvider).activeEpoch != epoch) return;
      _signature = null;
      widget.onUncertain?.call(false);
      widget.onDone?.call();
    } on Object catch (error) {
      if (!mounted || ref.read(sessionProvider).activeEpoch != epoch) return;
      if (error is StateError) _signature = null;
      widget.onUncertain?.call(error is! StateError);
      setState(
        () => _error = error is StateError
            ? acpText(
                context,
                '操作未接受，请等待状态同步后重试。',
                'Action not accepted. Wait for the updated state and retry.',
              )
            : acpText(
                context,
                '尚未确认，请重试同一操作。',
                'Not confirmed yet. Retry the same action.',
              ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _sending = false;
        });
        updateKeepAlive();
        if (ref.read(sessionProvider).activeEpoch == epoch) {
          widget.onBusyChanged?.call(false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = context.awikiTheme;
    final compact = context.awikiResponsive.isCompact;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CupertinoButton(
          key: ValueKey(
            'acp-${widget.action}:${widget.values['run_id'] ?? widget.session.key}',
          ),
          minimumSize: Size(
            44,
            widget.primary || compact || widget.child != null ? 44 : 28,
          ),
          alignment: widget.child == null && !widget.primary
              ? Alignment.topCenter
              : Alignment.center,
          padding: widget.child != null
              ? EdgeInsets.zero
              : EdgeInsets.symmetric(
                  horizontal: widget.primary ? 14 : 8,
                  vertical: widget.primary ? 10 : 2,
                ),
          color: widget.primary ? theme.primary : null,
          borderRadius: BorderRadius.circular(10),
          onPressed: widget.enabled && !_busy ? _send : null,
          child: Semantics(
            label: _sending
                ? acpText(
                    context,
                    '${widget.label}，处理中',
                    '${widget.label}, in progress',
                  )
                : null,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Visibility(
                  visible: !_sending,
                  maintainSize: true,
                  maintainState: true,
                  maintainAnimation: true,
                  child:
                      widget.child ??
                      Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: widget.primary ? 14 : 12,
                          height: 1.4,
                          color: widget.primary ? CupertinoColors.white : null,
                        ),
                      ),
                ),
                if (_sending)
                  Positioned.fill(
                    child: Center(
                      child: CupertinoActivityIndicator(
                        radius: 8,
                        color: widget.primary
                            ? CupertinoColors.white
                            : theme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _error!,
              style: TextStyle(fontSize: 12, height: 1.4, color: theme.danger),
            ),
          ),
      ],
    );
  }
}
