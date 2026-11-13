import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages SQLCipher database encryption keys backed by platform keystores.
/// Strictly enforces no hardcoded or default encryption keys.
class DatabaseKeyManager {
  DatabaseKeyManager({FlutterSecureStorage? secureStorage})
    : _secureStorage =
          secureStorage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  static const String _keyStorageKey = 'rivero_sqlcipher_master_key_v1';
  static const String _keyHashStorageKey = 'rivero_sqlcipher_key_hash_v1';

  final FlutterSecureStorage _secureStorage;

  /// Retrieve the existing master encryption key or securely generate a new one.
  Future<String> getOrCreateMasterKey() async {
    final existingKey = await _secureStorage.read(key: _keyStorageKey);
    if (existingKey != null && existingKey.isNotEmpty) {
      return existingKey;
    }

    // Generate a cryptographically secure 256-bit (32 bytes) random key
    final newKey = _generateSecureRandomKey();
    await _secureStorage.write(key: _keyStorageKey, value: newKey);

    // Persist SHA-256 verification checksum
    final keyHash = sha256.convert(utf8.encode(newKey)).toString();
    await _secureStorage.write(key: _keyHashStorageKey, value: keyHash);

    return newKey;
  }

  /// Verify that the stored key matches its integrity checksum.
  Future<bool> verifyKeyIntegrity() async {
    final key = await _secureStorage.read(key: _keyStorageKey);
    final storedHash = await _secureStorage.read(key: _keyHashStorageKey);

    if (key == null || storedHash == null) return false;

    final computedHash = sha256.convert(utf8.encode(key)).toString();
    return computedHash == storedHash;
  }

  /// Securely purge encryption material (used exclusively for factory wipe).
  Future<void> wipeKey() async {
    await _secureStorage.delete(key: _keyStorageKey);
    await _secureStorage.delete(key: _keyHashStorageKey);
  }

  String _generateSecureRandomKey() {
    final secureRandom = Random.secure();
    final values = List<int>.generate(32, (_) => secureRandom.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
