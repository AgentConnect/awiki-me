import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../awiki_sdk/awiki_anp_session.dart';
import '../awiki_sdk/awiki_service_client.dart';
import '../awiki_sdk/awiki_user_client.dart';
import '../../domain/entities/profile_patch.dart';
import '../../domain/entities/session_identity.dart';
import '../../domain/repositories/awiki_account_gateway.dart';
import '../../domain/services/did_registration_facade.dart';
import 'app_key_value_store.dart';
import 'dart_did_registration_facade.dart';
import 'document_picker_service.dart';

class AwikiAccountService implements AwikiAccountGateway {
  AwikiAccountService({
    required this.userServiceUrl,
    AppKeyValueStore? storage,
    DidRegistrationFacade? didRegistrationFacade,
    DocumentPickerService? documentPickerService,
    http.Client? httpClient,
    AwikiUserClient? userClient,
  }) : _storage = storage ?? SecureAppKeyValueStore(),
       _didRegistrationFacade =
           didRegistrationFacade ?? DartDidRegistrationFacade(),
       _documentPickerService = documentPickerService,
       _httpClient = httpClient ?? http.Client(),
       _userClient = userClient;

  factory AwikiAccountService.fromEnvironment({
    AppKeyValueStore? storage,
    DidRegistrationFacade? didRegistrationFacade,
    DocumentPickerService? documentPickerService,
  }) {
    const userServiceUrl = String.fromEnvironment(
      'AWIKI_USER_SERVICE_URL',
      defaultValue: 'https://awiki.ai',
    );
    return AwikiAccountService(
      userServiceUrl: userServiceUrl,
      storage: storage,
      didRegistrationFacade: didRegistrationFacade,
      documentPickerService: documentPickerService,
    );
  }

  final String userServiceUrl;
  final AppKeyValueStore _storage;
  final DidRegistrationFacade _didRegistrationFacade;
  final DocumentPickerService? _documentPickerService;
  final http.Client _httpClient;
  final AwikiUserClient? _userClient;

  static const String _activeCredentialKey = 'awiki_account_active_credential';
  static const String _credentialsKey = 'awiki_account_credentials';
  static const String _bundleVersion = '2';

  SessionIdentity? _session;

  AwikiUserClient get _users {
    return _userClient ??
        AwikiUserClient(
          serviceClient: AwikiServiceClient(
            baseUrl: userServiceUrl,
            httpClient: _httpClient,
          ),
          httpClient: _httpClient,
        );
  }

  @override
  Future<SessionIdentity?> currentSession() async {
    return _session ?? await restoreSession();
  }

  @override
  Future<SessionIdentity?> refreshSession() async {
    final session = await currentSession();
    if (session == null) {
      return null;
    }
    final refreshed = await _tryRecoverAuthTokenViaStoredIdentity();
    return refreshed ? _session : session;
  }

  @override
  Future<SessionIdentity?> restoreSession() async {
    if (_session != null) {
      return _session;
    }
    final activeName = await _storage.read(key: _activeCredentialKey);
    if (activeName == null || activeName.isEmpty) {
      return null;
    }
    final stored = await _loadCredential(activeName);
    if (stored == null) {
      await _storage.delete(key: _activeCredentialKey);
      return null;
    }
    _ensureE1Did(stored.session.did);
    _session = stored.session;
    await _refreshSessionOnRestore();
    return _session;
  }

  @override
  Future<AwikiAnpSession> currentAnpSession({
    bool requireSigning = false,
  }) async {
    final session = await currentSession();
    if (session == null || session.did.isEmpty) {
      throw StateError('No active awiki session. Please sign in first.');
    }
    final material = await _loadMaterial(session.credentialName);
    final anpSession = AwikiAnpSession(
      did: session.did,
      jwtToken: session.jwtToken ?? '',
      didDocument: material.didDocument,
      privateKeyPem: material.privateKeyPem,
    );
    if (!anpSession.isE1Did) {
      throw StateError('Only e1 DID identities are supported.');
    }
    if (requireSigning && !anpSession.canSign) {
      throw StateError('ANP signed request requires local DID key material.');
    }
    return anpSession;
  }

  @override
  Future<void> logout() async {
    _session = null;
    await _storage.delete(key: _activeCredentialKey);
  }

  @override
  Future<List<SessionIdentity>> listLocalCredentials() async {
    final credentials = await _loadCredentialCatalog();
    return credentials.where((item) => _isE1Did(item.did)).toList()
      ..sort((a, b) => a.credentialName.compareTo(b.credentialName));
  }

  @override
  Future<SessionIdentity> loginWithLocalCredential(
    String credentialName,
  ) async {
    final stored = await _loadCredential(credentialName);
    if (stored == null) {
      throw StateError('本地未找到凭证：$credentialName');
    }
    _ensureE1Did(stored.session.did);
    await _setActiveSession(stored.session);
    await _refreshSessionOnRestore();
    return _session!;
  }

  @override
  Future<void> deleteLocalCredential(String credentialName) async {
    final credentials = await _loadCredentialCatalog();
    final remaining = credentials
        .where((item) => item.credentialName != credentialName)
        .toList();
    await _writeCredentialCatalog(remaining);
    await _storage.delete(key: _materialKey(credentialName));
    if (_session?.credentialName == credentialName ||
        await _storage.read(key: _activeCredentialKey) == credentialName) {
      await logout();
    }
  }

  @override
  Future<String?> exportCurrentCredentialAsZip() async {
    final session = await currentSession();
    if (session == null) {
      throw StateError('当前没有已登录凭证可导出。');
    }
    final material = await _loadMaterial(session.credentialName);
    if (material.didDocument == null || material.privateKeyPem.isEmpty) {
      throw StateError('当前凭证缺少 DID 文档或 key-1 私钥。');
    }
    final service = _documentPickerService;
    if (service == null) {
      throw StateError('当前平台暂不支持导出身份凭证。');
    }
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'manifest.json',
          jsonEncode(<String, Object?>{
            'bundle_version': _bundleVersion,
            'credential_name': session.credentialName,
            'did': session.did,
            'display_name': session.displayName,
            'handle': session.handle,
            'exported_at': DateTime.now().toUtc().toIso8601String(),
          }),
        ),
      )
      ..addFile(
        ArchiveFile.string('session.json', jsonEncode(_sessionToJson(session))),
      )
      ..addFile(
        ArchiveFile.string(
          'did_document.json',
          jsonEncode(material.didDocument),
        ),
      )
      ..addFile(
        ArchiveFile.string('key-1-private.pem', material.privateKeyPem),
      );
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive) ?? <int>[]);
    if (bytes.isEmpty) {
      throw StateError('凭证打包失败，请稍后重试。');
    }
    return service.saveZipFile(
      fileName: _exportFileName(session),
      bytes: bytes,
    );
  }

  @override
  Future<SessionIdentity?> importCredentialFromZip() async {
    final service = _documentPickerService;
    if (service == null) {
      throw StateError('当前平台暂不支持导入身份凭证。');
    }
    final bytes = await service.pickZipFile();
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    final decoded = ZipDecoder().decodeBytes(bytes, verify: true);
    final files = <String, List<int>>{};
    for (final entry in decoded) {
      final name = _normalizeArchivePath(entry.name);
      if (name.isEmpty || !entry.isFile) {
        continue;
      }
      final content = entry.content;
      if (content is! List<int>) {
        throw const FormatException('ZIP 包内容损坏。');
      }
      files[name] = content;
    }
    final manifest = _decodeJsonMap(files['manifest.json'], 'manifest.json');
    final sessionPayload = _decodeJsonMap(
      files['session.json'],
      'session.json',
    );
    final didDocument = _decodeJsonMap(
      files['did_document.json'],
      'did_document.json',
    );
    final privateKeyPem = utf8.decode(
      files['key-1-private.pem'] ??
          (throw const FormatException('ZIP 包缺少 key-1-private.pem。')),
    );
    final session = _sessionFromJson(sessionPayload);
    final manifestDid = manifest['did']?.toString() ?? '';
    if (manifestDid.isNotEmpty && manifestDid != session.did) {
      throw const FormatException('ZIP 包 manifest 与 session DID 不一致。');
    }
    if (didDocument['id']?.toString() != session.did) {
      throw const FormatException('ZIP 包 DID 文档与 session DID 不一致。');
    }
    _ensureE1Did(session.did);
    if (privateKeyPem.trim().isEmpty) {
      throw const FormatException('ZIP 包 key-1 私钥为空。');
    }
    await _saveCredential(
      _StoredCredential(
        session: session,
        material: AccountCredentialMaterial(
          didDocument: didDocument,
          privateKeyPem: privateKeyPem,
          domain: _didDomain(),
        ),
      ),
    );
    return session;
  }

  @override
  Future<void> sendOtp({required String phone}) {
    return _users.sendOtp(phone: _normalizePhone(phone));
  }

  @override
  Future<void> sendEmailVerification({required String email}) {
    return _users.sendEmailVerification(baseUrl: userServiceUrl, email: email);
  }

  @override
  Future<bool> checkEmailVerified({required String email}) {
    return _users.checkEmailVerified(baseUrl: userServiceUrl, email: email);
  }

  @override
  Future<SessionIdentity> registerHandle({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  }) async {
    final normalizedHandle = _normalizeHandle(handle);
    final normalizedPhone = _normalizePhone(phone);
    return _registerHandleCore(
      pluginPayload: await _didRegistrationFacade.buildRegisterHandleParams(
        phone: normalizedPhone,
        otp: _sanitizeOtp(otp),
        handle: normalizedHandle,
        inviteCode: inviteCode,
        nickName: nickName,
      ),
      authParams: <String, Object?>{
        'phone': normalizedPhone,
        'otp_code': _sanitizeOtp(otp),
      },
      handle: normalizedHandle,
      inviteCode: inviteCode,
      nickName: nickName,
      profileMarkdown: profileMarkdown,
    );
  }

  @override
  Future<SessionIdentity> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  }) async {
    final normalizedHandle = _normalizeHandle(handle);
    final normalizedEmail = email.trim().toLowerCase();
    return _registerHandleCore(
      pluginPayload: await _didRegistrationFacade.buildRegisterHandleParams(
        email: normalizedEmail,
        handle: normalizedHandle,
        inviteCode: inviteCode,
        nickName: nickName,
      ),
      authParams: <String, Object?>{'email': normalizedEmail},
      handle: normalizedHandle,
      inviteCode: inviteCode,
      nickName: nickName,
      profileMarkdown: profileMarkdown,
    );
  }

  @override
  Future<SessionIdentity> recoverHandle({
    required String phone,
    required String otp,
    required String handle,
  }) async {
    final normalizedHandle = _normalizeHandle(handle);
    final normalizedPhone = _normalizePhone(phone);
    return _registerHandleCore(
      pluginPayload: await _didRegistrationFacade.buildRegisterHandleParams(
        phone: normalizedPhone,
        otp: _sanitizeOtp(otp),
        handle: normalizedHandle,
      ),
      authParams: <String, Object?>{
        'phone': normalizedPhone,
        'otp_code': _sanitizeOtp(otp),
        'handle': normalizedHandle,
      },
      handle: normalizedHandle,
      rpcMethod: 'recover_handle',
    );
  }

  Future<SessionIdentity> _registerHandleCore({
    required Map<String, Object?> pluginPayload,
    required Map<String, Object?> authParams,
    required String handle,
    String rpcMethod = 'register',
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  }) async {
    final params = <String, Object?>{
      ...pluginPayload,
      'handle': handle,
      ...authParams,
      if (inviteCode != null && inviteCode.isNotEmpty)
        'invite_code': inviteCode,
      if (nickName != null && nickName.isNotEmpty) 'name': nickName,
      'is_public': true,
    };
    final result = rpcMethod == 'recover_handle'
        ? await _users.recoverHandle(params: params)
        : await _users.register(params: params);
    final did = result['did']?.toString() ?? _extractDid(pluginPayload);
    final token = result['access_token']?.toString() ?? '';
    if (did.isEmpty || token.isEmpty) {
      throw StateError(
        'Handle registration succeeded but did/access_token is missing.',
      );
    }
    _ensureE1Did(did);
    final credentialName = handle;
    final session = SessionIdentity(
      did: did,
      credentialName: credentialName,
      displayName: nickName?.isNotEmpty == true ? nickName! : handle,
      handle: handle,
      jwtToken: token,
    );
    final material = _materialFromPayload(pluginPayload);
    await _saveCredential(
      _StoredCredential(session: session, material: material),
    );
    await _setActiveSession(session);
    if (profileMarkdown != null && profileMarkdown.isNotEmpty) {
      await _users.updateMe(
        bearerToken: token,
        patch: ProfilePatch(profileMarkdown: profileMarkdown).toUserPatch(),
      );
    }
    return session;
  }

  Future<void> _refreshSessionOnRestore() async {
    try {
      await _tryRecoverAuthTokenViaStoredIdentity();
    } catch (_) {
      // Auth recovery is best-effort during startup.
    }
  }

  Future<bool> _tryRecoverAuthTokenViaStoredIdentity() async {
    final current = _session;
    if (current == null) {
      return false;
    }
    final material = await _loadMaterial(current.credentialName);
    final didDocument = material.didDocument;
    if (didDocument == null || material.privateKeyPem.isEmpty) {
      return false;
    }
    if (didDocument['id']?.toString() != current.did) {
      return false;
    }
    final authorization = await _didRegistrationFacade.generateDidAuthHeader(
      didDocument: didDocument,
      privateKeyPem: material.privateKeyPem,
      domain: material.domain.isNotEmpty ? material.domain : _didDomain(),
    );
    final result = await _users.verifyDidAuth(
      authorization: authorization,
      domain: material.domain.isNotEmpty ? material.domain : _didDomain(),
    );
    final token = result['access_token']?.toString() ?? '';
    final did =
        result['did']?.toString() ??
        result['user_did']?.toString() ??
        current.did;
    if (token.isEmpty || did != current.did) {
      return false;
    }
    final refreshed = SessionIdentity(
      did: current.did,
      credentialName: current.credentialName,
      displayName: current.displayName,
      handle: current.handle,
      jwtToken: token,
    );
    await _saveCredential(
      _StoredCredential(session: refreshed, material: material),
    );
    await _setActiveSession(refreshed);
    return true;
  }

  Future<void> _setActiveSession(SessionIdentity session) async {
    _session = session;
    await _storage.write(
      key: _activeCredentialKey,
      value: session.credentialName,
    );
  }

  Future<void> _saveCredential(_StoredCredential credential) async {
    final credentials = await _loadCredentialCatalog();
    final merged = <String, SessionIdentity>{
      for (final item in credentials) item.credentialName: item,
      credential.session.credentialName: credential.session,
    }.values.toList();
    await _writeCredentialCatalog(merged);
    await _storage.write(
      key: _materialKey(credential.session.credentialName),
      value: jsonEncode(credential.material.toJson()),
    );
  }

  Future<_StoredCredential?> _loadCredential(String credentialName) async {
    final credentials = await _loadCredentialCatalog();
    final matches = credentials.where(
      (item) => item.credentialName == credentialName,
    );
    if (matches.isEmpty) {
      return null;
    }
    return _StoredCredential(
      session: matches.first,
      material: await _loadMaterial(credentialName),
    );
  }

  Future<List<SessionIdentity>> _loadCredentialCatalog() async {
    final raw = await _storage.read(key: _credentialsKey);
    if (raw == null || raw.isEmpty) {
      return const <SessionIdentity>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <SessionIdentity>[];
      }
      return decoded
          .whereType<Map<Object?, Object?>>()
          .map(
            (item) => _sessionFromJson(
              item.map<String, Object?>(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .where((item) => item.did.isNotEmpty)
          .toList();
    } catch (_) {
      return const <SessionIdentity>[];
    }
  }

  Future<void> _writeCredentialCatalog(List<SessionIdentity> credentials) {
    return _storage.write(
      key: _credentialsKey,
      value: jsonEncode(credentials.map(_sessionToJson).toList()),
    );
  }

  Future<AccountCredentialMaterial> _loadMaterial(String credentialName) async {
    final raw = await _storage.read(key: _materialKey(credentialName));
    if (raw == null || raw.isEmpty) {
      return const AccountCredentialMaterial();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const AccountCredentialMaterial();
      }
      return AccountCredentialMaterial.fromJson(
        decoded.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
    } catch (_) {
      return const AccountCredentialMaterial();
    }
  }

  AccountCredentialMaterial _materialFromPayload(Map<String, Object?> payload) {
    final didDocument = payload['did_document'];
    final privateKeyPem = payload['private_key_pem']?.toString() ?? '';
    if (didDocument is! Map || privateKeyPem.isEmpty) {
      throw StateError(
        'Dart DID registration did not return local key material.',
      );
    }
    return AccountCredentialMaterial(
      didDocument: didDocument.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      ),
      privateKeyPem: privateKeyPem,
      domain: payload['domain']?.toString() ?? _didDomain(),
    );
  }

  Map<String, Object?> _decodeJsonMap(List<int>? bytes, String name) {
    if (bytes == null) {
      throw FormatException('ZIP 包缺少 $name。');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw FormatException('$name 格式不正确。');
    }
    return decoded.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  Map<String, Object?> _sessionToJson(SessionIdentity session) {
    return <String, Object?>{
      'did': session.did,
      'credential_name': session.credentialName,
      'display_name': session.displayName,
      'handle': session.handle,
      'jwt_token': session.jwtToken,
    };
  }

  SessionIdentity _sessionFromJson(Map<String, Object?> json) {
    return SessionIdentity(
      did: json['did']?.toString() ?? '',
      credentialName: json['credential_name']?.toString() ?? 'default',
      displayName: json['display_name']?.toString() ?? 'AWiki Me',
      handle: json['handle']?.toString(),
      jwtToken: json['jwt_token']?.toString(),
    );
  }

  String _extractDid(Map<String, Object?> payload) {
    final did = payload['did']?.toString();
    if (did != null && did.isNotEmpty) {
      return did;
    }
    final didDocument = payload['did_document'];
    if (didDocument is Map) {
      return didDocument['id']?.toString() ?? '';
    }
    return '';
  }

  String _normalizePhone(String phone) {
    final raw = phone.trim();
    final intlPattern = RegExp(r'^\+\d{1,3}\d{6,14}$');
    final cnLocalPattern = RegExp(r'^1[3-9]\d{9}$');
    if (raw.startsWith('+')) {
      if (!intlPattern.hasMatch(raw)) {
        throw ArgumentError('手机号格式不正确，请使用 +国家码手机号，例如 +8613800138000');
      }
      return raw;
    }
    if (cnLocalPattern.hasMatch(raw)) {
      return '+86$raw';
    }
    throw ArgumentError('手机号格式不正确，请输入国际格式或中国大陆 11 位手机号');
  }

  String _normalizeHandle(String handle) {
    final normalized = handle.trim().toLowerCase();
    final pattern = RegExp(r'^[a-z0-9-]{2,32}$');
    if (!pattern.hasMatch(normalized)) {
      throw ArgumentError('handle 仅支持小写字母、数字、中划线，长度 2-32，不能包含下划线');
    }
    return normalized;
  }

  String _sanitizeOtp(String code) => code.replaceAll(RegExp(r'\s+'), '');

  String _didDomain() {
    final configured = Uri.tryParse(userServiceUrl)?.host ?? '';
    return configured.isEmpty ? 'awiki.ai' : configured;
  }

  String _materialKey(String credentialName) {
    return 'awiki_account_material_$credentialName';
  }

  String _exportFileName(SessionIdentity session) {
    final formatter = DateFormat('yyyyMMddHHmmss');
    final rawName = session.handle?.isNotEmpty == true
        ? session.handle!
        : session.credentialName;
    final safeName = rawName.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    return 'awiki-credential-$safeName-${formatter.format(DateTime.now())}.zip';
  }

  String _normalizeArchivePath(String rawPath) {
    final replaced = rawPath.replaceAll('\\', '/').trim();
    if (replaced.isEmpty || replaced.startsWith('/')) {
      return '';
    }
    final segments = <String>[];
    for (final segment in replaced.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        throw const FormatException('ZIP 包包含非法路径。');
      }
      segments.add(segment);
    }
    return segments.join('/');
  }

  bool _isE1Did(String did) => did.trim().split(':').last.startsWith('e1_');

  void _ensureE1Did(String did) {
    if (!_isE1Did(did)) {
      throw StateError('Only e1 DID identities are supported.');
    }
  }
}

class AccountCredentialMaterial {
  const AccountCredentialMaterial({
    this.didDocument,
    this.privateKeyPem = '',
    this.domain = '',
  });

  final Map<String, Object?>? didDocument;
  final String privateKeyPem;
  final String domain;

  factory AccountCredentialMaterial.fromJson(Map<String, Object?> json) {
    final rawDocument = json['did_document'];
    Map<String, Object?>? didDocument;
    if (rawDocument is Map) {
      didDocument = rawDocument.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return AccountCredentialMaterial(
      didDocument: didDocument,
      privateKeyPem: json['private_key_pem']?.toString() ?? '',
      domain: json['domain']?.toString() ?? '',
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'did_document': didDocument,
      'private_key_pem': privateKeyPem,
      'domain': domain,
    };
  }
}

class _StoredCredential {
  const _StoredCredential({required this.session, required this.material});

  final SessionIdentity session;
  final AccountCredentialMaterial material;
}

extension on ProfilePatch {
  Map<String, Object?> toUserPatch() {
    return <String, Object?>{
      if (nickName != null) 'nick_name': nickName,
      if (bio != null) 'bio': bio,
      if (tags != null) 'tags': tags,
      if (profileMarkdown != null) 'profile_md': profileMarkdown,
    };
  }
}
