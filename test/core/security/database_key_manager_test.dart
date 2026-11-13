import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/security/database_key_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('DatabaseKeyManager tests', () {
    test(
      'generates cryptographically secure 256-bit key on first call',
      () async {
        final keyManager = DatabaseKeyManager();
        final key = await keyManager.getOrCreateMasterKey();

        expect(key, isNotEmpty);
        expect(key.length, equals(64)); // 32 bytes in hex = 64 characters
      },
    );

    test('retrieves existing key on subsequent calls (idempotent)', () async {
      final keyManager = DatabaseKeyManager();
      final key1 = await keyManager.getOrCreateMasterKey();
      final key2 = await keyManager.getOrCreateMasterKey();

      expect(key1, equals(key2));
    });

    test('verifies key integrity with SHA-256 hash', () async {
      final keyManager = DatabaseKeyManager();
      await keyManager.getOrCreateMasterKey();

      final isValid = await keyManager.verifyKeyIntegrity();
      expect(isValid, isTrue);
    });

    test('wipeKey deletes stored key and hash', () async {
      final keyManager = DatabaseKeyManager();
      final key1 = await keyManager.getOrCreateMasterKey();

      await keyManager.wipeKey();
      final isValid = await keyManager.verifyKeyIntegrity();
      expect(isValid, isFalse);

      final key2 = await keyManager.getOrCreateMasterKey();
      expect(key2, isNot(equals(key1))); // Fresh key generated
    });
  });
}
