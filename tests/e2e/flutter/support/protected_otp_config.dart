import 'dart:io';

import 'package:yaml/yaml.dart';

final class ProtectedOtpConfig {
  const ProtectedOtpConfig._({required this.phone, required this.code});

  factory ProtectedOtpConfig.load(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('Protected OTP config file was not found.');
    }
    final raw = loadYaml(file.readAsStringSync());
    if (raw is! YamlMap) {
      throw StateError('Protected OTP config must be a YAML object.');
    }
    final otp = raw['otp'];
    if (otp is! YamlMap) {
      throw StateError('Protected OTP config must contain otp settings.');
    }
    final phone = otp['phone']?.toString().trim() ?? '';
    final code = otp['code']?.toString().trim() ?? '';
    if (phone.isEmpty ||
        code.length != 6 ||
        !code.codeUnits.every((unit) => unit >= 0x30 && unit <= 0x39)) {
      throw StateError('Protected OTP config is invalid.');
    }
    return ProtectedOtpConfig._(phone: phone, code: code);
  }

  final String phone;
  final String code;

  @override
  String toString() => 'ProtectedOtpConfig(<redacted>)';
}
