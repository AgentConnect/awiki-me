part of 'acp_task_status.dart';

class AcpModelBar extends ConsumerWidget {
  const AcpModelBar({
    super.key,
    required this.scope,
    required this.session,
    this.online = true,
  });
  final AcpModelScope scope;
  final AcpSession? session;
  final bool online;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operation = ref.watch(acpModelControllerProvider(scope));
    final epoch = ref.watch(sessionProvider.select((s) => s.activeEpoch));
    final known =
        session?.data['model_configuration_ready'] == true ||
        session?.data['model_id'] is String;
    if (!operation.attempted &&
        !known &&
        online &&
        session?.busy != true &&
        session?.contextLost != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted ||
            ref.read(sessionProvider).activeEpoch != epoch) {
          return;
        }
        final controller = ref.read(acpModelControllerProvider(scope).notifier);
        if (!ref.read(acpModelControllerProvider(scope)).attempted) {
          unawaited(controller.prepare());
        }
      });
    }
    if (session != null) return AcpSessionOptions(session: session!);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: _AcpModelOperationStatus(
        scope: scope,
        fallback: online
            ? acpText(context, '正在获取模型…', 'Loading models…')
            : acpText(
                context,
                '设备离线，暂时无法获取模型',
                'Device offline; models unavailable',
              ),
      ),
    );
  }
}

class _AcpModelOperationStatus extends ConsumerWidget {
  const _AcpModelOperationStatus({required this.scope, this.fallback});
  final AcpModelScope scope;
  final String? fallback;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(acpModelControllerProvider(scope));
    final text = switch (state.phase) {
      AcpModelPhase.idle => fallback,
      AcpModelPhase.sending =>
        state.targetModel == null
            ? acpText(context, '正在获取模型…', 'Loading models…')
            : acpText(context, '正在切换模型…', 'Changing model…'),
      AcpModelPhase.uncertain => acpText(
        context,
        '尚未确认，请重试同一操作',
        'Not confirmed yet. Retry the same action.',
      ),
      AcpModelPhase.synchronizing => acpText(
        context,
        '正在同步模型配置…',
        'Syncing model configuration…',
      ),
      AcpModelPhase.failed =>
        state.targetModel == null
            ? acpText(
                context,
                '未能获取模型配置，请重试',
                'Could not load model configuration. Retry.',
              )
            : acpText(
                context,
                '未能切换模型，当前模型保持不变',
                'Could not change the model. The current model is unchanged.',
              ),
    };
    if (text == null) return const SizedBox.shrink();
    final theme = context.awikiTheme;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        if (state.phase == AcpModelPhase.sending ||
            state.phase == AcpModelPhase.synchronizing)
          const CupertinoActivityIndicator(radius: 7),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: theme.secondaryText,
          ),
        ),
        if (state.phase == AcpModelPhase.uncertain ||
            state.phase == AcpModelPhase.failed ||
            state.phase == AcpModelPhase.synchronizing)
          CupertinoButton(
            key: const Key('acp-model-retry'),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            onPressed: () =>
                ref.read(acpModelControllerProvider(scope).notifier).retry(),
            child: Text(
              acpText(context, '重试', 'Retry'),
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}
