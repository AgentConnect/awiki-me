class AgentRegistrationToken {
  const AgentRegistrationToken({
    required this.token,
    this.expiresAt,
    this.tokenId,
  });

  final String token;
  final DateTime? expiresAt;
  final String? tokenId;
}

class InstallCommand {
  const InstallCommand({
    required this.token,
    required this.command,
    required this.fallbackCommand,
    required this.installerUrl,
    required this.packageUrlTemplate,
  });

  final AgentRegistrationToken token;
  final String command;
  final String fallbackCommand;
  final String installerUrl;
  final String packageUrlTemplate;
}
