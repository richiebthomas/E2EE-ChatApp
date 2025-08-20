import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

class SecureStorageService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // Storage keys
  static const String _authTokenKey = 'auth_token';
  static const String _userDataKey = 'user_data';
  static const String _identityPrivateKeyKey = 'identity_private_key';
  static const String _identityPublicKeyKey = 'identity_public_key';
  static const String _signedPrekeyPrivateKey = 'signed_prekey_private';
  static const String _signedPrekeyPublicKey = 'signed_prekey_public';
  static const String _oneTimePrekeyPrefix = 'otp_private_';
  static const String _sessionStatePrefix = 'session_';

  // Auth token management
  Future<void> saveAuthToken(String token) async {
    await _storage.write(key: _authTokenKey, value: token);
  }

  Future<String?> getAuthToken() async {
    return await _storage.read(key: _authTokenKey);
  }

  Future<void> clearAuthToken() async {
    await _storage.delete(key: _authTokenKey);
  }

  // User data management
  Future<void> saveUserData(Map<String, dynamic> userData) async {
    await _storage.write(key: _userDataKey, value: json.encode(userData));
  }

  Future<Map<String, dynamic>?> getUserData() async {
    final data = await _storage.read(key: _userDataKey);
    if (data != null) {
      return json.decode(data) as Map<String, dynamic>;
    }
    return null;
  }

  Future<void> clearUserData() async {
    await _storage.delete(key: _userDataKey);
  }

  // Identity key management
  Future<void> saveIdentityKeyPair({
    required String privateKey,
    required String publicKey,
  }) async {
    await Future.wait([
      _storage.write(key: _identityPrivateKeyKey, value: privateKey),
      _storage.write(key: _identityPublicKeyKey, value: publicKey),
    ]);
  }

  Future<Map<String, String>?> getIdentityKeyPair() async {
    final results = await Future.wait([
      _storage.read(key: _identityPrivateKeyKey),
      _storage.read(key: _identityPublicKeyKey),
    ]);

    final privateKey = results[0];
    final publicKey = results[1];

    if (privateKey != null && publicKey != null) {
      return {
        'privateKey': privateKey,
        'publicKey': publicKey,
      };
    }
    return null;
  }

  // Signed prekey management
  Future<void> saveSignedPrekeyPair({
    required String privateKey,
    required String publicKey,
    required int keyId,
  }) async {
    await Future.wait([
      _storage.write(key: _signedPrekeyPrivateKey, value: privateKey),
      _storage.write(key: _signedPrekeyPublicKey, value: publicKey),
      _storage.write(key: '${_signedPrekeyPrivateKey}_id', value: keyId.toString()),
    ]);
  }

  Future<Map<String, dynamic>?> getSignedPrekeyPair() async {
    final results = await Future.wait([
      _storage.read(key: _signedPrekeyPrivateKey),
      _storage.read(key: _signedPrekeyPublicKey),
      _storage.read(key: '${_signedPrekeyPrivateKey}_id'),
    ]);

    final privateKey = results[0];
    final publicKey = results[1];
    final keyIdStr = results[2];

    if (privateKey != null && publicKey != null && keyIdStr != null) {
      return {
        'privateKey': privateKey,
        'publicKey': publicKey,
        'keyId': int.parse(keyIdStr),
      };
    }
    return null;
  }

  // One-time prekey management
  Future<void> saveOneTimePrekeyPrivate({
    required int keyId,
    required String privateKey,
  }) async {
    await _storage.write(
      key: '$_oneTimePrekeyPrefix$keyId',
      value: privateKey,
    );
  }

  Future<String?> getOneTimePrekeyPrivate(int keyId) async {
    return await _storage.read(key: '$_oneTimePrekeyPrefix$keyId');
  }

  Future<void> deleteOneTimePrekeyPrivate(int keyId) async {
    await _storage.delete(key: '$_oneTimePrekeyPrefix$keyId');
  }

  Future<List<int>> getStoredOneTimePrekeyIds() async {
    final allKeys = await _storage.readAll();
    final otpKeys = allKeys.keys
        .where((key) => key.startsWith(_oneTimePrekeyPrefix))
        .map((key) => int.parse(key.replaceFirst(_oneTimePrekeyPrefix, '')))
        .toList();
    
    otpKeys.sort();
    return otpKeys;
  }

  // Session state management (for Double Ratchet)
  Future<void> saveSessionState({
    required String userId,
    required Map<String, dynamic> sessionData,
  }) async {
    await _storage.write(
      key: '$_sessionStatePrefix$userId',
      value: json.encode(sessionData),
    );
  }

  Future<Map<String, dynamic>?> getSessionState(String userId) async {
    final data = await _storage.read(key: '$_sessionStatePrefix$userId');
    if (data != null) {
      return json.decode(data) as Map<String, dynamic>;
    }
    return null;
  }

  Future<void> deleteSessionState(String userId) async {
    await _storage.delete(key: '$_sessionStatePrefix$userId');
  }

  Future<List<String>> getSessionUserIds() async {
    final allKeys = await _storage.readAll();
    return allKeys.keys
        .where((key) => key.startsWith(_sessionStatePrefix))
        .map((key) => key.replaceFirst(_sessionStatePrefix, ''))
        .toList();
  }

  // Clear all data (logout)
  Future<void> clearAllData() async {
    await _storage.deleteAll();
  }

  // Development/Debug methods
  Future<Map<String, String>> getAllKeys() async {
    // Only use for debugging - never in production
    return await _storage.readAll();
  }

  // Export/import all local Signal state as a JSON blob
  Future<String> exportAllSensitiveData() async {
    final all = await _storage.readAll();
    return json.encode(all);
  }

  Future<void> importAllSensitiveData(String blobJson) async {
    final map = (json.decode(blobJson) as Map).cast<String, String>();
    for (final entry in map.entries) {
      await _storage.write(key: entry.key, value: entry.value);
    }
  }

  Future<bool> hasIdentityKeys() async {
    final keys = await getIdentityKeyPair();
    return keys != null;
  }

  Future<bool> hasSignedPrekey() async {
    final keys = await getSignedPrekeyPair();
    return keys != null;
  }

  Future<int> getOneTimePrekeyCount() async {
    final ids = await getStoredOneTimePrekeyIds();
    return ids.length;
  }

  // Generic data storage for Signal Protocol sessions
  Future<void> saveData(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<String?> getData(String key) async {
    return await _storage.read(key: key);
  }
}
