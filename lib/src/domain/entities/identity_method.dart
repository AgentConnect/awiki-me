enum IdentityDidMethod { wba, web }

/// Core method support only; the live Registry still controls write authority.
class IdentityMethodCapabilities {
  const IdentityMethodCapabilities({
    required this.method,
    required this.handleRecovery,
    required this.rootImport,
    required this.rootTransfer,
    required this.servicesUpdate,
  });

  final IdentityDidMethod method;
  final bool handleRecovery;
  final bool rootImport;
  final bool rootTransfer;
  final bool servicesUpdate;
}

class IdentityDocumentService {
  const IdentityDocumentService({
    required this.id,
    required this.type,
    required this.endpoint,
    this.serviceDid,
    this.profiles = const [],
    this.securityProfiles = const [],
  });

  final String id;
  final String type;
  final String endpoint;
  final String? serviceDid;
  final List<String> profiles;
  final List<String> securityProfiles;

  // These entries use their established product flows. Core also enforces this.
  bool get isProtected => const {
    'AgentDescription',
    'ANPHandleService',
    'ANPMessageService',
  }.contains(type);
}

class IdentityServicesSnapshot {
  const IdentityServicesSnapshot({
    required this.services,
    required this.pending,
  });

  final List<IdentityDocumentService> services;
  final bool pending;
}

class PendingIdentityRegistration {
  const PendingIdentityRegistration({
    required this.did,
    required this.fullHandle,
    required this.method,
    required this.displayName,
    required this.verificationKind,
    required this.phase,
  });

  final String did;
  final String fullHandle;
  final IdentityDidMethod method;
  final String displayName;
  final String verificationKind;
  final String phase;
}
