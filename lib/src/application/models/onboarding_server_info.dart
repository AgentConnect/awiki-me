class OnboardingServerInfo {
  const OnboardingServerInfo({
    required this.schemaVersion,
    required this.service,
    required this.identity,
    this.deployment,
  });

  final int schemaVersion;
  final OnboardingServerServiceInfo service;
  final OnboardingIdentityCapabilities identity;
  final Map<String, Object?>? deployment;

  factory OnboardingServerInfo.fromJson(Map<String, Object?> json) {
    final schemaVersion = _intValue(json['schema_version']) ?? 0;
    if (schemaVersion != 1) {
      throw const FormatException('Unsupported server-info schema version.');
    }
    return OnboardingServerInfo(
      schemaVersion: schemaVersion,
      service: OnboardingServerServiceInfo.fromJson(
        _objectValue(json['service'], 'service'),
      ),
      identity: OnboardingIdentityCapabilities.fromJson(
        _objectValue(json['identity'], 'identity'),
      ),
      deployment: _optionalObjectValue(json['deployment']),
    );
  }

  factory OnboardingServerInfo.userServiceDefault() {
    return const OnboardingServerInfo(
      schemaVersion: 1,
      service: OnboardingServerServiceInfo(
        kind: 'user-service',
        name: 'AWiki User Service',
      ),
      identity: OnboardingIdentityCapabilities(
        handleRegistration: OnboardingHandleRegistrationCapabilities(
          enabled: true,
          defaultMethod: OnboardingIdentityMethodId.phone,
          availability: 'open',
          methods: <OnboardingIdentityMethod>[
            OnboardingIdentityMethod(
              id: OnboardingIdentityMethodId.phone,
              enabled: true,
              verification: OnboardingVerificationRequirement(
                required: true,
                type: OnboardingVerificationType.smsOtp,
              ),
            ),
            OnboardingIdentityMethod(
              id: OnboardingIdentityMethodId.email,
              enabled: true,
              verification: OnboardingVerificationRequirement(
                required: true,
                type: OnboardingVerificationType.emailActivation,
              ),
            ),
          ],
        ),
        handleRecovery: OnboardingHandleRecoveryCapabilities(
          methods: <OnboardingIdentityMethod>[
            OnboardingIdentityMethod(
              id: OnboardingIdentityMethodId.phone,
              enabled: true,
              verification: OnboardingVerificationRequirement(
                required: true,
                type: OnboardingVerificationType.smsOtp,
              ),
            ),
          ],
        ),
      ),
    );
  }

  factory OnboardingServerInfo.openServerDefault({
    String didDomain = 'localhost',
  }) {
    return OnboardingServerInfo(
      schemaVersion: 1,
      service: const OnboardingServerServiceInfo(
        kind: 'awiki-open-server',
        name: 'AWiki Open Server',
      ),
      identity: const OnboardingIdentityCapabilities(
        handleRegistration: OnboardingHandleRegistrationCapabilities(
          enabled: true,
          defaultMethod: OnboardingIdentityMethodId.phone,
          availability: 'open',
          methods: <OnboardingIdentityMethod>[
            OnboardingIdentityMethod(
              id: OnboardingIdentityMethodId.phone,
              enabled: true,
              verification: OnboardingVerificationRequirement(
                required: false,
                type: OnboardingVerificationType.none,
              ),
            ),
          ],
        ),
        handleRecovery: OnboardingHandleRecoveryCapabilities(
          methods: <OnboardingIdentityMethod>[],
        ),
      ),
      deployment: <String, Object?>{'did_domain': didDomain},
    );
  }

  List<OnboardingIdentityMethod> get registrationMethods {
    if (!identity.handleRegistration.enabled) {
      return const <OnboardingIdentityMethod>[];
    }
    return identity.handleRegistration.enabledMethods;
  }

  OnboardingIdentityMethod? get defaultRegistrationMethod {
    final methods = registrationMethods;
    if (methods.isEmpty) {
      return null;
    }
    final preferred = identity.handleRegistration.defaultMethod;
    if (preferred != null) {
      for (final method in methods) {
        if (method.id == preferred) {
          return method;
        }
      }
    }
    return methods.first;
  }

  OnboardingIdentityMethod? registrationMethod(OnboardingIdentityMethodId id) {
    for (final method in registrationMethods) {
      if (method.id == id) {
        return method;
      }
    }
    return null;
  }

  bool get supportsPhoneOtpRegistration {
    return registrationMethod(
          OnboardingIdentityMethodId.phone,
        )?.verification.type ==
        OnboardingVerificationType.smsOtp;
  }

  bool get supportsEmailActivationRegistration {
    return registrationMethod(
          OnboardingIdentityMethodId.email,
        )?.verification.type ==
        OnboardingVerificationType.emailActivation;
  }

  bool get supportsPhoneNoVerificationRegistration {
    final phone = registrationMethod(OnboardingIdentityMethodId.phone);
    return phone != null &&
        phone.verification.type == OnboardingVerificationType.none &&
        !phone.verification.required;
  }

  bool get supportsPhoneOtpRecovery {
    for (final method in identity.handleRecovery.enabledMethods) {
      if (method.id == OnboardingIdentityMethodId.phone &&
          method.verification.type == OnboardingVerificationType.smsOtp) {
        return true;
      }
    }
    return false;
  }
}

class OnboardingServerServiceInfo {
  const OnboardingServerServiceInfo({required this.kind, required this.name});

  final String kind;
  final String name;

  factory OnboardingServerServiceInfo.fromJson(Map<String, Object?> json) {
    return OnboardingServerServiceInfo(
      kind: _stringValue(json['kind']) ?? 'unknown',
      name: _stringValue(json['name']) ?? 'Unknown server',
    );
  }
}

class OnboardingIdentityCapabilities {
  const OnboardingIdentityCapabilities({
    required this.handleRegistration,
    required this.handleRecovery,
  });

  final OnboardingHandleRegistrationCapabilities handleRegistration;
  final OnboardingHandleRecoveryCapabilities handleRecovery;

  factory OnboardingIdentityCapabilities.fromJson(Map<String, Object?> json) {
    return OnboardingIdentityCapabilities(
      handleRegistration: OnboardingHandleRegistrationCapabilities.fromJson(
        _objectValue(
          json['handle_registration'],
          'identity.handle_registration',
        ),
      ),
      handleRecovery: OnboardingHandleRecoveryCapabilities.fromJson(
        _objectValue(json['handle_recovery'], 'identity.handle_recovery'),
      ),
    );
  }
}

class OnboardingHandleRegistrationCapabilities {
  const OnboardingHandleRegistrationCapabilities({
    required this.enabled,
    required this.methods,
    this.defaultMethod,
    this.availability,
  });

  final bool enabled;
  final OnboardingIdentityMethodId? defaultMethod;
  final List<OnboardingIdentityMethod> methods;
  final String? availability;

  List<OnboardingIdentityMethod> get enabledMethods {
    return methods.where((method) => method.enabled).toList(growable: false);
  }

  factory OnboardingHandleRegistrationCapabilities.fromJson(
    Map<String, Object?> json,
  ) {
    return OnboardingHandleRegistrationCapabilities(
      enabled: json['enabled'] == true,
      defaultMethod: OnboardingIdentityMethodId.parse(
        _stringValue(json['default_method']),
      ),
      availability: _stringValue(json['availability']),
      methods: _methodList(
        json['methods'],
        'identity.handle_registration.methods',
      ),
    );
  }
}

class OnboardingHandleRecoveryCapabilities {
  const OnboardingHandleRecoveryCapabilities({required this.methods});

  final List<OnboardingIdentityMethod> methods;

  List<OnboardingIdentityMethod> get enabledMethods {
    return methods.where((method) => method.enabled).toList(growable: false);
  }

  factory OnboardingHandleRecoveryCapabilities.fromJson(
    Map<String, Object?> json,
  ) {
    return OnboardingHandleRecoveryCapabilities(
      methods: _methodList(json['methods'], 'identity.handle_recovery.methods'),
    );
  }
}

class OnboardingIdentityMethod {
  const OnboardingIdentityMethod({
    required this.id,
    required this.enabled,
    required this.verification,
  });

  final OnboardingIdentityMethodId id;
  final bool enabled;
  final OnboardingVerificationRequirement verification;

  factory OnboardingIdentityMethod.fromJson(Map<String, Object?> json) {
    final id = OnboardingIdentityMethodId.parse(_stringValue(json['id']));
    if (id == null) {
      throw const FormatException('Unsupported onboarding identity method.');
    }
    return OnboardingIdentityMethod(
      id: id,
      enabled: json['enabled'] == true,
      verification: OnboardingVerificationRequirement.fromJson(
        _objectValue(json['verification'], 'method.verification'),
      ),
    );
  }
}

class OnboardingVerificationRequirement {
  const OnboardingVerificationRequirement({
    required this.required,
    required this.type,
  });

  final bool required;
  final OnboardingVerificationType type;

  factory OnboardingVerificationRequirement.fromJson(
    Map<String, Object?> json,
  ) {
    final type = OnboardingVerificationType.parse(_stringValue(json['type']));
    if (type == null) {
      throw const FormatException('Unsupported onboarding verification type.');
    }
    return OnboardingVerificationRequirement(
      required: json['required'] == true,
      type: type,
    );
  }
}

enum OnboardingIdentityMethodId {
  phone,
  email,
  handleOnly;

  static OnboardingIdentityMethodId? parse(String? value) {
    return switch (value) {
      'phone' => OnboardingIdentityMethodId.phone,
      'email' => OnboardingIdentityMethodId.email,
      'handle_only' => OnboardingIdentityMethodId.handleOnly,
      _ => null,
    };
  }

  String get wireName {
    return switch (this) {
      OnboardingIdentityMethodId.phone => 'phone',
      OnboardingIdentityMethodId.email => 'email',
      OnboardingIdentityMethodId.handleOnly => 'handle_only',
    };
  }
}

enum OnboardingVerificationType {
  smsOtp,
  emailActivation,
  none;

  static OnboardingVerificationType? parse(String? value) {
    return switch (value) {
      'sms_otp' => OnboardingVerificationType.smsOtp,
      'email_activation' => OnboardingVerificationType.emailActivation,
      'none' => OnboardingVerificationType.none,
      _ => null,
    };
  }
}

List<OnboardingIdentityMethod> _methodList(Object? raw, String fieldName) {
  if (raw is! List) {
    throw FormatException('$fieldName must be a list.');
  }
  return raw
      .map(
        (item) =>
            OnboardingIdentityMethod.fromJson(_objectValue(item, fieldName)),
      )
      .toList(growable: false);
}

Map<String, Object?> _objectValue(Object? raw, String fieldName) {
  if (raw is Map) {
    return raw.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
  throw FormatException('$fieldName must be an object.');
}

Map<String, Object?>? _optionalObjectValue(Object? raw) {
  if (raw == null) {
    return null;
  }
  return _objectValue(raw, 'deployment');
}

String? _stringValue(Object? raw) => raw?.toString();

int? _intValue(Object? raw) {
  if (raw is int) {
    return raw;
  }
  return int.tryParse(raw?.toString() ?? '');
}
