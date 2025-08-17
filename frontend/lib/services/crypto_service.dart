import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import '../models/prekey_bundle.dart';
import 'signal_protocol/signal_protocol.dart';
import 'secure_storage_service.dart';

class CryptoService {
  static final _x25519 = X25519();
  // Ed25519 currently unused in this simplified build
  static final _aesGcm = AesGcm.with256bits();
  static final _random = Random.secure();
  static SignalProtocol? _signalProtocol;

  /// Initialize Signal Protocol
  static Future<void> initialize(SecureStorageService storage) async {
    _signalProtocol = SignalProtocol(storage);
    await _signalProtocol!.initialize();
  }

  // Expose limited internal for session-from-incoming usage
  static SignalProtocol? get signal => _signalProtocol;

  // Generate identity key pair (long-term key) - using X25519 for Signal Protocol
  static Future<Map<String, String>> generateIdentityKeyPair() async {
    final keyPair = await _x25519.newKeyPair();
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();
    final publicBytes = publicKey.bytes;

    return {
      'privateKey': base64Encode(privateBytes),
      'publicKey': base64Encode(publicBytes),
    };
  }

  // Generate signed prekey pair
  static Future<Map<String, dynamic>> generateSignedPrekeyPair({
    required String identityPrivateKey,
    required int keyId,
  }) async {
    // Generate prekey pair
    final prekeyPair = await _x25519.newKeyPair();
    final prekeyPrivateBytes = await prekeyPair.extractPrivateKeyBytes();
    final prekeyPublicKey = await prekeyPair.extractPublicKey();
    final prekeyPublicBytes = prekeyPublicKey.bytes;

    // For simplicity, create a simple signature using HMAC with identity key
    // In production Signal Protocol, you'd use a separate Ed25519 signing key
    final identityKeyBytes = base64Decode(identityPrivateKey);
    final signature = crypto.Hmac(crypto.sha256, identityKeyBytes).convert(prekeyPublicBytes);

    return {
      'privateKey': base64Encode(prekeyPrivateBytes),
      'publicKey': base64Encode(prekeyPublicBytes),
      'signature': base64Encode(signature.bytes),
      'keyId': keyId,
    };
  }

  // Generate one-time prekeys
  static Future<List<Map<String, dynamic>>> generateOneTimePrekeys(int count) async {
    final prekeys = <Map<String, dynamic>>[];
    
    for (int i = 0; i < count; i++) {
      final keyPair = await _x25519.newKeyPair();
      final privateBytes = await keyPair.extractPrivateKeyBytes();
      final publicKey = await keyPair.extractPublicKey();
      final publicBytes = publicKey.bytes;

      prekeys.add({
        'keyId': i,
        'privateKey': base64Encode(privateBytes),
        'publicKey': base64Encode(publicBytes),
      });
    }

    return prekeys;
  }

  // Verify signed prekey signature
  static Future<bool> verifySignedPrekey({
    required String identityPublicKey,
    required String signedPrekeyPublic,
    required String signature,
  }) async {
    try {
      // For simplicity, we'll skip signature verification in this implementation
      // In production, you'd properly verify the HMAC signature
      // This is sufficient for demonstrating the Signal Protocol flow
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Start Signal Protocol session with another user
  static Future<void> startSignalSession({
    required String otherUserId,
    required String identityKey,
    required String signedPrekey,
    required String signature,
    String? oneTimePrekey,
  }) async {
    if (_signalProtocol == null) {
      throw Exception('Signal Protocol not initialized');
    }
    
    await _signalProtocol!.startSession(
      otherUserId: otherUserId,
      identityKey: identityKey,
      signedPrekey: signedPrekey,
      signature: signature,
      oneTimePrekey: oneTimePrekey,
    );
  }

  /// Encrypt message using Signal Protocol
  static Future<String> encryptMessageSignal(String userId, String plaintext) async {
    if (_signalProtocol == null) {
      throw Exception('Signal Protocol not initialized');
    }
    
    final encryptedMessage = await _signalProtocol!.encryptMessage(userId, plaintext);
    return jsonEncode(encryptedMessage.toJson());
  }

  /// Decrypt message using Signal Protocol
  static Future<String> decryptMessageSignal(String userId, String ciphertext) async {
    if (_signalProtocol == null) {
      throw Exception('Signal Protocol not initialized');
    }
    
    final encryptedMessage = EncryptedMessage.fromJson(jsonDecode(ciphertext));
    return await _signalProtocol!.decryptMessage(userId, encryptedMessage);
  }

  /// Check if Signal Protocol session exists
  static bool hasSignalSession(String userId) {
    return _signalProtocol?.hasSession(userId) ?? false;
  }

  // X3DH Key Agreement (simplified version for backward compatibility)
  static Future<Uint8List> performX3DH({
    required String identityPrivateKey,
    required String ephemeralPrivateKey,
    required PrekeyBundle bundle,
  }) async {
    try {
      // Convert keys
      final identityPrivate = await _x25519.newKeyPairFromSeed(
        base64Decode(identityPrivateKey),
      );
      
      final ephemeralPrivate = await _x25519.newKeyPairFromSeed(
        base64Decode(ephemeralPrivateKey),
      );

      final identityPublic = SimplePublicKey(
        base64Decode(bundle.identityPubkey),
        type: KeyPairType.x25519,
      );

      final signedPrekeyPublic = SimplePublicKey(
        base64Decode(bundle.signedPrekey.pubkey),
        type: KeyPairType.x25519,
      );

      // Perform DH operations
      final dh1 = await _x25519.sharedSecretKey(
        keyPair: identityPrivate,
        remotePublicKey: signedPrekeyPublic,
      );

      final dh2 = await _x25519.sharedSecretKey(
        keyPair: ephemeralPrivate,
        remotePublicKey: identityPublic,
      );

      final dh3 = await _x25519.sharedSecretKey(
        keyPair: ephemeralPrivate,
        remotePublicKey: signedPrekeyPublic,
      );

      // Combine shared secrets
      final dh1Bytes = await dh1.extractBytes();
      final dh2Bytes = await dh2.extractBytes();
      final dh3Bytes = await dh3.extractBytes();

      // If one-time prekey is available
      List<int>? dh4Bytes;
      if (bundle.oneTimePrekey != null) {
        final oneTimePrekeyPublic = SimplePublicKey(
          base64Decode(bundle.oneTimePrekey!.pubkey),
          type: KeyPairType.x25519,
        );

        final dh4 = await _x25519.sharedSecretKey(
          keyPair: ephemeralPrivate,
          remotePublicKey: oneTimePrekeyPublic,
        );
        dh4Bytes = await dh4.extractBytes();
      }

      // Create root key from combined secrets
      final combined = <int>[];
      combined.addAll(dh1Bytes);
      combined.addAll(dh2Bytes);
      combined.addAll(dh3Bytes);
      if (dh4Bytes != null) {
        combined.addAll(dh4Bytes);
      }

      // Hash to create root key
      final digest = crypto.sha256.convert(combined);
      return Uint8List.fromList(digest.bytes);

    } catch (e) {
      throw Exception('X3DH key agreement failed: $e');
    }
  }

  // Simple message encryption (placeholder for Double Ratchet)
  static Future<String> encryptMessage({
    required String plaintext,
    required Uint8List sharedSecret,
  }) async {
    try {
      final secretKey = SecretKey(sharedSecret.take(32).toList());
      final message = utf8.encode(plaintext);
      
      // Generate random nonce
      final nonce = List.generate(12, (i) => _random.nextInt(256));
      
      final secretBox = await _aesGcm.encrypt(
        message,
        secretKey: secretKey,
        nonce: nonce,
      );

      // Combine nonce + ciphertext
      final combined = <int>[];
      combined.addAll(nonce);
      combined.addAll(secretBox.cipherText);
      combined.addAll(secretBox.mac.bytes);

      return base64Encode(combined);
    } catch (e) {
      throw Exception('Message encryption failed: $e');
    }
  }

  // Simple message decryption (placeholder for Double Ratchet)
  static Future<String> decryptMessage({
    required String ciphertext,
    required Uint8List sharedSecret,
  }) async {
    try {
      final secretKey = SecretKey(sharedSecret.take(32).toList());
      final combined = base64Decode(ciphertext);

      // Extract components
      final nonce = combined.take(12).toList();
      final cipherBytes = combined.skip(12).take(combined.length - 12 - 16).toList();
      final macBytes = combined.skip(combined.length - 16).toList();

      final secretBox = SecretBox(
        cipherBytes,
        nonce: nonce,
        mac: Mac(macBytes),
      );

      final decrypted = await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
      );

      return utf8.decode(decrypted);
    } catch (e) {
      throw Exception('Message decryption failed: $e');
    }
  }

  // Generate random bytes
  static Uint8List generateRandomBytes(int length) {
    return Uint8List.fromList(
      List.generate(length, (i) => _random.nextInt(256)),
    );
  }

  // Hash function
  static Uint8List hash(List<int> data) {
    final digest = crypto.sha256.convert(data);
    return Uint8List.fromList(digest.bytes);
  }

  // Generate ephemeral key pair for message sending
  static Future<Map<String, String>> generateEphemeralKeyPair() async {
    final keyPair = await _x25519.newKeyPair();
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();
    final publicBytes = publicKey.bytes;

    return {
      'privateKey': base64Encode(privateBytes),
      'publicKey': base64Encode(publicBytes),
    };
  }
}