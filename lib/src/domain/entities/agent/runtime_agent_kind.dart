const runtimeWorkspaceModeRouteRoot = 'route-root';
const runtimeWorkspaceModeSharedRoot = 'shared-root';
const runtimeWorkspaceModeWorktreePerTask = 'worktree-per-task';

const runtimeSandboxReadOnly = 'read-only';
const runtimeSandboxWorkspaceWrite = 'workspace-write';

enum RuntimeAgentKind { hermes, codex, claudeCode }

extension RuntimeAgentKindInfo on RuntimeAgentKind {
  String get runtime => switch (this) {
    RuntimeAgentKind.hermes => 'hermes',
    RuntimeAgentKind.codex => 'codex',
    RuntimeAgentKind.claudeCode => 'claude-code',
  };

  String? get driverId => switch (this) {
    RuntimeAgentKind.hermes => null,
    RuntimeAgentKind.codex => 'codex',
    RuntimeAgentKind.claudeCode => 'claude-code',
  };

  String get displayLabel => switch (this) {
    RuntimeAgentKind.hermes => 'Hermes',
    RuntimeAgentKind.codex => 'Codex',
    RuntimeAgentKind.claudeCode => 'Claude Code',
  };

  String get defaultDisplayNamePrefix => displayLabel;

  String get handlePlaceholder => switch (this) {
    RuntimeAgentKind.hermes => 'my-hermes',
    RuntimeAgentKind.codex => 'my-codex',
    RuntimeAgentKind.claudeCode => 'my-claude',
  };

  bool get isGenericCli => driverId != null;

  bool get canCreate => switch (this) {
    RuntimeAgentKind.hermes || RuntimeAgentKind.codex => true,
    RuntimeAgentKind.claudeCode => false,
  };

  Map<String, Object?> get defaultDriverConfig => switch (this) {
    RuntimeAgentKind.codex => const <String, Object?>{'ephemeral': false},
    RuntimeAgentKind.hermes ||
    RuntimeAgentKind.claudeCode => const <String, Object?>{},
  };

  String get description => switch (this) {
    RuntimeAgentKind.hermes => '适合通用任务和稳定对话',
    RuntimeAgentKind.codex => '使用本机 Codex CLI 处理代码任务',
    RuntimeAgentKind.claudeCode => '暂未支持，敬请期待。',
  };
}

class RuntimeAgentCreateOptions {
  const RuntimeAgentCreateOptions({
    required this.kind,
    required this.handle,
    required this.displayName,
    this.workspaceMode = runtimeWorkspaceModeRouteRoot,
    this.sandbox = runtimeSandboxReadOnly,
    this.model,
  });

  final RuntimeAgentKind kind;
  final String handle;
  final String displayName;
  final String workspaceMode;
  final String sandbox;
  final String? model;

  Map<String, Object?> get driverConfig => kind.defaultDriverConfig;
}

RuntimeAgentKind runtimeAgentKindFromRuntime(String? runtime) {
  final normalized = runtime?.trim().toLowerCase().replaceAll('_', '-');
  return switch (normalized) {
    'codex' || 'codex-cli' => RuntimeAgentKind.codex,
    'claude-code' || 'claude' => RuntimeAgentKind.claudeCode,
    _ => RuntimeAgentKind.hermes,
  };
}
