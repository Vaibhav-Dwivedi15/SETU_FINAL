import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setu_app/features/sms/data/repositories/sms_repository.dart';
import 'package:setu_app/mesh/services/signing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BLOCK 3 -- mobile security regressions:
///  * the Ed25519 private key seed lives ONLY in flutter_secure_storage (never SharedPreferences,
///    never bundled, never referenced outside SigningService)
///  * log redaction helpers
///  * Android release/backup configuration (source-level; the built APK is inspected separately)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  group('private key storage', () {
    final secure = <String, String>{};

    setUp(() {
      secure.clear();
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'read':
            return secure[call.arguments['key']];
          case 'write':
            secure[call.arguments['key'] as String] = call.arguments['value'] as String;
            return null;
          default:
            return null;
        }
      });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    test('a newly generated seed is written to secure storage only', () async {
      final pub = await SigningService().getOrCreatePublicKeyHex();
      expect(pub, hasLength(64));
      expect(secure.keys, ['setu_signing_private_key_seed']);
      expect(secure['setu_signing_private_key_seed'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(secure['setu_signing_private_key_seed'], isNot(pub), reason: 'the private seed is not the public key');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty, reason: 'nothing key-related may reach SharedPreferences');
    });

    test('the same identity is reloaded from secure storage (not regenerated)', () async {
      final first = await SigningService().getOrCreatePublicKeyHex();
      final second = await SigningService().getOrCreatePublicKeyHex();
      expect(second, first);
      expect(secure, hasLength(1));
    });
  });

  group('repository-wide key hygiene (source scan)', () {
    final libFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('the seed storage key is referenced only by SigningService', () {
      final users = libFiles.where((f) => f.readAsStringSync().contains('setu_signing_private_key_seed')).map((f) => f.path).toList();
      expect(users, ['lib/mesh/services/signing_service.dart']);
    });

    test('no file mixes SharedPreferences with key/seed material', () {
      for (final f in libFiles) {
        final s = f.readAsStringSync();
        if (s.contains('SharedPreferences')) {
          expect(RegExp(r'(private[_ ]?key|extractPrivateKeyBytes|seedHex|_privateKeySeedKey)', caseSensitive: false).hasMatch(s), isFalse,
              reason: f.path);
        }
      }
    });

    test('private key bytes are never logged or printed', () {
      for (final f in libFiles) {
        final s = f.readAsStringSync();
        expect(RegExp(r'(print|debugPrint|developer\.log)\([^;]*(extractPrivateKeyBytes|_keyPair|seed)').hasMatch(s), isFalse, reason: f.path);
      }
    });

    test('no private key / keystore file is bundled as an asset', () {
      final assets = Directory('assets').existsSync() ? Directory('assets').listSync(recursive: true).whereType<File>() : <File>[];
      for (final a in assets) {
        expect(RegExp(r'\.(pem|jks|keystore|p12|key)$').hasMatch(a.path), isFalse, reason: a.path);
      }
    });
  });

  group('log redaction', () {
    test('phone numbers are reduced to their last two digits', () {
      expect(SmsRepository.maskNumber('+919876543210'), '***10');
      expect(SmsRepository.maskNumber('98765 43210'), '***10');
      expect(SmsRepository.maskNumber('7'), '***');
      expect(SmsRepository.maskNumber(''), '***');
      expect(SmsRepository.maskNumber('+919876543210'), isNot(contains('98765')));
    });
  });

  group('Android configuration (source)', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    test('backup is disabled and rules exclude every domain', () {
      expect(manifest, contains('android:allowBackup="false"'));
      for (final f in ['data_extraction_rules.xml', 'backup_rules.xml']) {
        final xml = File('android/app/src/main/res/xml/$f').readAsStringSync();
        for (final d in ['root', 'file', 'database', 'sharedpref', 'external']) {
          expect(xml, contains('<exclude domain="$d"'));
        }
        expect(xml, isNot(contains('<include')));
      }
    });

    test('cleartext traffic is off and only system CAs are trusted', () {
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
      final nsc = File('android/app/src/main/res/xml/network_security_config.xml').readAsStringSync();
      expect(nsc, contains('cleartextTrafficPermitted="false"'));
      expect(nsc, isNot(contains('src="user"')));
    });

    test('only MainActivity is exported; the mesh service is not', () {
      final exported = RegExp(r'<(activity|service|receiver|provider)[^>]*android:exported="true"[^>]*>').allMatches(manifest).toList();
      expect(exported, hasLength(1));
      expect(exported.single.group(0), contains('.MainActivity'));
      expect(manifest, contains('android:name="com.setu.mesh.MeshForegroundService"'));
      expect(RegExp(r'MeshForegroundService"[^>]*android:exported="false"', dotAll: true).hasMatch(manifest), isTrue);
    });

    test('release signing has no debug fallback and refuses to build unsigned', () {
      expect(gradle, isNot(contains('getByName("debug")')));
      expect(gradle, contains('SETU RELEASE BUILD REFUSED'));
      expect(gradle, contains('signingConfigs.findByName("release")'));
    });

    test('no signing material is committed', () {
      final tracked = Process.runSync('git', ['ls-files', '..'], workingDirectory: '.').stdout as String;
      expect(RegExp(r'(\.jks|\.keystore|/key\.properties)$', multiLine: true).hasMatch(tracked), isFalse);
    });
  });
}
