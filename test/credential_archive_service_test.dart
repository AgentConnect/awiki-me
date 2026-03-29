import 'dart:convert';
import 'dart:io';

import 'package:awiki_me/src/data/services/credential_archive_service.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CredentialArchiveService', () {
    late CredentialArchiveService service;
    late Directory tempDir;

    setUp(() async {
      service = CredentialArchiveService();
      tempDir =
          await Directory.systemTemp.createTemp('credential-archive-test-');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('生成的导出文件名包含用户名简写并清洗特殊字符', () {
      const session = SessionIdentity(
        did: 'did:test:123',
        credentialName: 'default user',
        displayName: '测试昵称',
        handle: 'alice.long-name@demo',
      );

      final fileName = service.buildExportFileName(
        session: session,
        now: DateTime(2026, 3, 29, 8, 9, 10),
      );

      expect(
        fileName,
        'awiki-credential-alice_long-n-default_user-20260329080910.zip',
      );
    });

    test('handle 为空时会回退到 displayName 或 credentialName', () {
      const session = SessionIdentity(
        did: 'did:test:123',
        credentialName: 'cred-01',
        displayName: 'Display Name',
      );

      final fileName = service.buildExportFileName(
        session: session,
        now: DateTime(2026, 3, 29, 8, 9, 10),
      );

      expect(
        fileName,
        'awiki-credential-Display_Name-cred-01-20260329080910.zip',
      );
    });

    test('打包和解包会保留 manifest 与 credential 内容', () async {
      final credentialDir = Directory('${tempDir.path}/source')..createSync();
      File('${credentialDir.path}/identity.json').writeAsStringSync(
        jsonEncode(<String, Object?>{
          'did': 'did:test:123',
          'name': 'Alice',
          'handle': 'alice',
        }),
      );
      File('${credentialDir.path}/auth.json').writeAsStringSync(
        jsonEncode(<String, Object?>{'jwt_token': 'token-123'}),
      );
      File('${credentialDir.path}/key-1-private.pem')
          .writeAsStringSync('private-key');
      Directory('${credentialDir.path}/ton_wallet').createSync();
      File('${credentialDir.path}/ton_wallet/wallet.enc')
          .writeAsStringSync('encrypted');

      final manifest = <String, Object?>{
        'bundle_version': '1',
        'credential_name': 'default',
        'dir_name': 'uid-123',
        'did': 'did:test:123',
        'unique_id': 'uid-123',
        'display_name': 'Alice',
        'handle': 'alice',
        'created_at': '2026-03-29T00:00:00Z',
        'exported_at': '2026-03-29T08:09:10Z',
      };

      final zipBytes = service.buildZip(
        manifest: manifest,
        credentialDirectory: credentialDir,
      );

      final unpacked = service.unpackZip(
        bytes: zipBytes,
        destinationRoot: Directory('${tempDir.path}/import'),
      );

      expect(unpacked.manifest['credential_name'], 'default');
      expect(
        File('${unpacked.credentialDirectory.path}/identity.json').existsSync(),
        isTrue,
      );
      expect(
        File('${unpacked.credentialDirectory.path}/ton_wallet/wallet.enc')
            .existsSync(),
        isTrue,
      );
    });

    test('路径穿越 zip 会被拒绝', () {
      final archiveBytes = _zipWithTraversal();

      expect(
        () => service.unpackZip(
          bytes: archiveBytes,
          destinationRoot: Directory('${tempDir.path}/import-2'),
        ),
        throwsFormatException,
      );
    });
  });
}

List<int> _zipWithTraversal() {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode(<String, Object?>{
          'bundle_version': '1',
          'credential_name': 'default',
          'dir_name': 'uid-123',
          'did': 'did:test:123',
          'unique_id': 'uid-123',
          'display_name': 'Alice',
          'handle': 'alice',
          'created_at': '2026-03-29T00:00:00Z',
          'exported_at': '2026-03-29T08:09:10Z',
        }),
      ),
    )
    ..addFile(
      ArchiveFile.string('../outside/identity.json', '{"did":"did:test:123"}'),
    )
    ..addFile(
      ArchiveFile.string('credential/auth.json', '{"jwt_token":"token-123"}'),
    )
    ..addFile(
      ArchiveFile.string('credential/key-1-private.pem', 'private-key'),
    );
  return ZipEncoder().encode(archive) ?? <int>[];
}
