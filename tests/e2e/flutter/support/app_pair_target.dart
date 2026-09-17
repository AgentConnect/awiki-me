/// Mirrors the owning suite's audited targets inside both real App processes.
/// Only the ACP repair suite opts into its explicitly selected second tenant.
void validateAppPairRemoteTarget({
  required bool acp,
  required String didDomain,
  required Iterable<String> serviceUrls,
}) {
  final allowed = {'awiki.info', if (acp) 'anpclaw.com'};
  if (!allowed.contains(didDomain)) {
    throw StateError('The App-pair DID target is not audited.');
  }
  for (final value in serviceUrls) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host != didDomain) {
      throw StateError('The App-pair service target is not audited.');
    }
  }
}
