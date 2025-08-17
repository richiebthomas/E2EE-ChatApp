import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import '../secure_storage_service.dart';

/// Simplified but robust Signal Protocol implementation
class SignalProtocol {
  final SecureStorageService _storage;
  final Map<String, SignalSession> _sessions = {};
  final X25519 _x25519 = X25519();
  final AesGcm _aes = AesGcm.with256bits();
  
  SignalProtocol(this._storage);

  Future<void> initialize() async {
    await _loadSessions();
    print('🔐 Signal Protocol initialized with ${_sessions.length} sessions');
  }

  /// Start a new session as initiator
  Future<SignalSession> startSession({
    required String otherUserId,
    required String identityKey,
    required String signedPrekey,
    required String signature,
    String? oneTimePrekey,
  }) async {
    try {
      print('🔑 Starting Signal session with: $otherUserId');
      
      // Get our keys
      final ourKeys = await _getOurKeys();
      
      // Perform X3DH key agreement
      final sharedSecret = await _performX3DH(
        ourKeys: ourKeys,
        theirIdentityKey: identityKey,
        theirSignedPrekey: signedPrekey,
        theirOneTimePrekey: oneTimePrekey,
      );
      
      // Create session with deterministic key assignment
      final session = await _createSession(
        otherUserId: otherUserId,
        sharedSecret: sharedSecret,
        ourKeys: ourKeys,
        theirSignedPrekey: signedPrekey,
        isInitiator: true,
      );
      
      _sessions[otherUserId] = session;
      await _saveSession(session);
      
      print('✅ Session created successfully');
      return session;
      
    } catch (e) {
      print('❌ Failed to start session: $e');
      rethrow;
    }
  }

  /// Start session from incoming message
  Future<SignalSession> startSessionFromIncoming({
    required String otherUserId,
    required String senderEphemeralKey,
    required String senderIdentityKey,
  }) async {
    try {
      print('🔑 Starting session from incoming message');
      
      // Get our keys
      final ourKeys = await _getOurKeys();
      
      // Perform X3DH as receiver
      final sharedSecret = await _performX3DHReceiver(
        ourKeys: ourKeys,
        theirIdentityKey: senderIdentityKey,
        theirEphemeralKey: senderEphemeralKey,
      );
      
      // Create session
      final session = await _createSession(
        otherUserId: otherUserId,
        sharedSecret: sharedSecret,
        ourKeys: ourKeys,
        theirSignedPrekey: senderEphemeralKey,
        isInitiator: false,
      );
      
      _sessions[otherUserId] = session;
      await _saveSession(session);
      
      print('✅ Session created from incoming message');
      return session;
      
    } catch (e) {
      print('❌ Failed to start session from incoming: $e');
      rethrow;
    }
  }

  /// Encrypt a message
  Future<EncryptedMessage> encryptMessage(String userId, String plaintext) async {
    final session = _sessions[userId];
    if (session == null) {
      throw Exception('No session found for user: $userId');
    }

    try {
      // Get current message number
      final messageNumber = session.sendMessageNumber;
      
      // Derive message key deterministically
      final messageKey = await _deriveMessageKey(
        baseKey: session.sendKey,
        messageNumber: messageNumber,
        userId: session.userId,
        isOutgoing: true,
      );
      
      // Encrypt the message
      final encryptedData = await _encryptWithKey(messageKey, plaintext);
      
      // Create message
      final message = EncryptedMessage(
        ciphertext: encryptedData.ciphertext,
        nonce: encryptedData.nonce,
        authTag: encryptedData.authTag,
        header: MessageHeader(
          senderId: await _getCurrentUserId(),
          messageNumber: messageNumber,
          sessionId: session.sessionId,
        ),
      );
      
      // Increment message counter
      session.sendMessageNumber++;
      await _saveSession(session);
      
      print('🔒 Message encrypted (msg #$messageNumber)');
      return message;
      
    } catch (e) {
      print('❌ Failed to encrypt message: $e');
      rethrow;
    }
  }

  /// Decrypt a message
  Future<String> decryptMessage(String userId, EncryptedMessage encryptedMessage) async {
    var session = _sessions[userId];
    
    // If no session, try to create one from the message
    if (session == null) {
      print('📥 No session found, creating from incoming message');
      session = await startSessionFromIncoming(
        otherUserId: userId,
        senderEphemeralKey: '', // Will be derived from message
        senderIdentityKey: '', // Will be derived from message
      );
    }

    try {
      final messageNumber = encryptedMessage.header.messageNumber;
      final senderId = encryptedMessage.header.senderId;
      
      // Determine if this is our own message
      final currentUserId = await _getCurrentUserId();
      final isOwnMessage = senderId == currentUserId;
      
      // Derive message key
      final messageKey = await _deriveMessageKey(
        baseKey: isOwnMessage ? session.sendKey : session.receiveKey,
        messageNumber: messageNumber,
        userId: session.userId,
        isOutgoing: isOwnMessage,
      );
      
      // Decrypt the message
      final plaintext = await _decryptWithKey(
        messageKey,
        encryptedMessage.ciphertext,
        encryptedMessage.nonce,
        encryptedMessage.authTag,
      );
      
      // Update receive counter if it's not our own message
      if (!isOwnMessage && messageNumber >= session.receiveMessageNumber) {
        session.receiveMessageNumber = messageNumber + 1;
        await _saveSession(session);
      }
      
      print('🔓 Message decrypted (msg #$messageNumber, own: $isOwnMessage)');
      return plaintext;
      
    } catch (e) {
      print('❌ Failed to decrypt message: $e');
      rethrow;
    }
  }

  /// Perform X3DH key agreement as initiator
  Future<Uint8List> _performX3DH({
    required UserKeys ourKeys,
    required String theirIdentityKey,
    required String theirSignedPrekey,
    String? theirOneTimePrekey,
  }) async {
    final theirIdentityPublic = SimplePublicKey(
      base64Decode(theirIdentityKey),
      type: KeyPairType.x25519,
    );
    
    final theirSignedPrekeyPublic = SimplePublicKey(
      base64Decode(theirSignedPrekey),
      type: KeyPairType.x25519,
    );

    // DH1 = DH(IK_A, SPK_B)
    final dh1 = await _x25519.sharedSecretKey(
      keyPair: ourKeys.identityKeyPair,
      remotePublicKey: theirSignedPrekeyPublic,
    );

    // DH2 = DH(EK_A, IK_B)
    final dh2 = await _x25519.sharedSecretKey(
      keyPair: ourKeys.ephemeralKeyPair,
      remotePublicKey: theirIdentityPublic,
    );

    // DH3 = DH(EK_A, SPK_B)
    final dh3 = await _x25519.sharedSecretKey(
      keyPair: ourKeys.ephemeralKeyPair,
      remotePublicKey: theirSignedPrekeyPublic,
    );

    // Combine all DH outputs
    final combined = <int>[];
    combined.addAll(await dh1.extractBytes());
    combined.addAll(await dh2.extractBytes());
    combined.addAll(await dh3.extractBytes());

    // Add one-time prekey if available
    if (theirOneTimePrekey != null) {
      final theirOneTimePrekeyPublic = SimplePublicKey(
        base64Decode(theirOneTimePrekey),
        type: KeyPairType.x25519,
      );
      
      final dh4 = await _x25519.sharedSecretKey(
        keyPair: ourKeys.ephemeralKeyPair,
        remotePublicKey: theirOneTimePrekeyPublic,
      );
      combined.addAll(await dh4.extractBytes());
    }

    return Uint8List.fromList(combined);
  }

  /// Perform X3DH as receiver
  Future<Uint8List> _performX3DHReceiver({
    required UserKeys ourKeys,
    required String theirIdentityKey,
    required String theirEphemeralKey,
  }) async {
    final theirIdentityPublic = SimplePublicKey(
      base64Decode(theirIdentityKey),
      type: KeyPairType.x25519,
    );
    
    final theirEphemeralPublic = SimplePublicKey(
      base64Decode(theirEphemeralKey),
      type: KeyPairType.x25519,
    );

    // Same DH operations but from receiver perspective
    final dh1 = await _x25519.sharedSecretKey(
      keyPair: ourKeys.signedPrekeyPair,
      remotePublicKey: theirIdentityPublic,
    );

    final dh2 = await _x25519.sharedSecretKey(
      keyPair: ourKeys.identityKeyPair,
      remotePublicKey: theirEphemeralPublic,
    );

    final dh3 = await _x25519.sharedSecretKey(
      keyPair: ourKeys.signedPrekeyPair,
      remotePublicKey: theirEphemeralPublic,
    );

    final combined = <int>[];
    combined.addAll(await dh1.extractBytes());
    combined.addAll(await dh2.extractBytes());
    combined.addAll(await dh3.extractBytes());

    return Uint8List.fromList(combined);
  }

  /// Create a session with deterministic key assignment
  Future<SignalSession> _createSession({
    required String otherUserId,
    required Uint8List sharedSecret,
    required UserKeys ourKeys,
    required String theirSignedPrekey,
    required bool isInitiator,
  }) async {
    // Derive root key from shared secret
    final rootKey = await _hkdf(sharedSecret, 'RootKey', 32);
    
    // Create deterministic session ID
    final currentUserId = await _getCurrentUserId();
    final users = [currentUserId, otherUserId]..sort();
    final sessionId = await _hash('${users[0]}_${users[1]}');
    
    // Derive send and receive keys deterministically
    // Lower user ID gets KeyA for sending, KeyB for receiving
    // Higher user ID gets KeyB for sending, KeyA for receiving
    final keyA = await _hkdf(rootKey, 'KeyA', 32);
    final keyB = await _hkdf(rootKey, 'KeyB', 32);
    
    final isLowerUserId = currentUserId.compareTo(otherUserId) < 0;
    final sendKey = base64Encode(isLowerUserId ? keyA : keyB);
    final receiveKey = base64Encode(isLowerUserId ? keyB : keyA);
    
    return SignalSession(
      userId: otherUserId,
      sessionId: sessionId,
      rootKey: base64Encode(rootKey),
      sendKey: sendKey,
      receiveKey: receiveKey,
      sendMessageNumber: 0,
      receiveMessageNumber: 0,
      theirPublicKey: theirSignedPrekey,
      isInitiator: isInitiator,
    );
  }

  /// Derive message key deterministically
  Future<String> _deriveMessageKey({
    required String baseKey,
    required int messageNumber,
    required String userId,
    required bool isOutgoing,
  }) async {
    final info = 'MessageKey_${userId}_${isOutgoing ? 'out' : 'in'}_$messageNumber';
    final keyBytes = await _hkdf(base64Decode(baseKey), info, 32);
    return base64Encode(keyBytes);
  }

  /// Encrypt with authenticated encryption
  Future<EncryptionResult> _encryptWithKey(String messageKey, String plaintext) async {
    final keyBytes = base64Decode(messageKey);
    final secretKey = SecretKey(keyBytes);
    final plainData = utf8.encode(plaintext);
    
    final secretBox = await _aes.encrypt(plainData, secretKey: secretKey);
    
    return EncryptionResult(
      ciphertext: base64Encode(secretBox.cipherText),
      nonce: base64Encode(secretBox.nonce),
      authTag: base64Encode(secretBox.mac.bytes),
    );
  }

  /// Decrypt with authenticated decryption
  Future<String> _decryptWithKey(String messageKey, String ciphertext, String nonce, String authTag) async {
    final keyBytes = base64Decode(messageKey);
    final secretKey = SecretKey(keyBytes);
    
    final secretBox = SecretBox(
      base64Decode(ciphertext),
      nonce: base64Decode(nonce),
      mac: Mac(base64Decode(authTag)),
    );
    
    final decryptedData = await _aes.decrypt(secretBox, secretKey: secretKey);
    return utf8.decode(decryptedData);
  }

  /// HKDF implementation
  Future<Uint8List> _hkdf(Uint8List inputKeyMaterial, String info, int length) async {
    // Step 1: Extract (simplified with zero salt)
    final salt = Uint8List(32);
    final hmacExtract = crypto.Hmac(crypto.sha256, salt);
    final prk = hmacExtract.convert(inputKeyMaterial).bytes;
    
    // Step 2: Expand
    final infoBytes = utf8.encode(info);
    final hmacExpand = crypto.Hmac(crypto.sha256, prk);
    
    final result = <int>[];
    final blockSize = 32;
    final numBlocks = (length + blockSize - 1) ~/ blockSize;
    
    List<int> previousBlock = [];
    
    for (int i = 1; i <= numBlocks; i++) {
      final blockInput = <int>[];
      blockInput.addAll(previousBlock);
      blockInput.addAll(infoBytes);
      blockInput.add(i);
      
      final block = hmacExpand.convert(blockInput).bytes;
      result.addAll(block);
      previousBlock = block;
    }
    
    return Uint8List.fromList(result.take(length).toList());
  }

  /// Hash function
  Future<String> _hash(String input) async {
    final bytes = utf8.encode(input);
    final digest = crypto.sha256.convert(bytes);
    return base64Encode(digest.bytes);
  }

  /// Get our cryptographic keys
  Future<UserKeys> _getOurKeys() async {
    final identityKeys = await _storage.getIdentityKeyPair();
    final signedPrekeys = await _storage.getSignedPrekeyPair();
    
    if (identityKeys?.isEmpty != false || signedPrekeys?.isEmpty != false) {
      throw Exception('Local keys not found - please re-login');
    }
    
    final identityKeyPair = await _x25519.newKeyPairFromSeed(
      base64Decode(identityKeys!['privateKey']!),
    );
    
    final signedPrekeyPair = await _x25519.newKeyPairFromSeed(
      base64Decode(signedPrekeys!['privateKey']!),
    );
    
    final ephemeralKeyPair = await _x25519.newKeyPair();
    
    return UserKeys(
      identityKeyPair: identityKeyPair,
      signedPrekeyPair: signedPrekeyPair,
      ephemeralKeyPair: ephemeralKeyPair,
    );
  }

  /// Get current user ID
  Future<String> _getCurrentUserId() async {
    final userData = await _storage.getUserData();
    if (userData?.isEmpty != false) {
      throw Exception('User data not found');
    }
    return userData!['id']?.toString() ?? '';
  }

  /// Save session to storage
  Future<void> _saveSession(SignalSession session) async {
    await _storage.saveData(
      'signal_session_${session.userId}',
      jsonEncode(session.toJson()),
    );
  }

  /// Load all sessions from storage
  Future<void> _loadSessions() async {
    try {
      final allKeys = await _storage.getAllKeys();
      for (final key in allKeys.keys) {
        if (key.startsWith('signal_session_')) {
          final sessionData = await _storage.getData(key);
          if (sessionData != null && sessionData.isNotEmpty) {
            final userId = key.substring('signal_session_'.length);
            final sessionJson = jsonDecode(sessionData);
            final session = SignalSession.fromJson(sessionJson);
            _sessions[userId] = session;
            print('📱 Loaded session for user: $userId');
          }
        }
      }
    } catch (e) {
      print('⚠️ Failed to load sessions: $e');
    }
  }

  /// Remove session
  Future<void> removeSession(String userId) async {
    _sessions.remove(userId);
    await _storage.saveData('signal_session_$userId', '');
  }

  /// Check if session exists
  bool hasSession(String userId) {
    return _sessions.containsKey(userId);
  }
}

/// User's cryptographic keys
class UserKeys {
  final KeyPair identityKeyPair;
  final KeyPair signedPrekeyPair;
  final KeyPair ephemeralKeyPair;

  UserKeys({
    required this.identityKeyPair,
    required this.signedPrekeyPair,
    required this.ephemeralKeyPair,
  });
}

/// Signal Protocol session state (simplified)
class SignalSession {
  final String userId;
  final String sessionId;
  final String rootKey;
  final String sendKey;
  final String receiveKey;
  int sendMessageNumber;
  int receiveMessageNumber;
  final String theirPublicKey;
  final bool isInitiator;

  SignalSession({
    required this.userId,
    required this.sessionId,
    required this.rootKey,
    required this.sendKey,
    required this.receiveKey,
    required this.sendMessageNumber,
    required this.receiveMessageNumber,
    required this.theirPublicKey,
    required this.isInitiator,
  });

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'sessionId': sessionId,
      'rootKey': rootKey,
      'sendKey': sendKey,
      'receiveKey': receiveKey,
      'sendMessageNumber': sendMessageNumber,
      'receiveMessageNumber': receiveMessageNumber,
      'theirPublicKey': theirPublicKey,
      'isInitiator': isInitiator,
    };
  }

  factory SignalSession.fromJson(Map<String, dynamic> json) {
    return SignalSession(
      userId: json['userId'] as String,
      sessionId: json['sessionId'] as String,
      rootKey: json['rootKey'] as String,
      sendKey: json['sendKey'] as String,
      receiveKey: json['receiveKey'] as String,
      sendMessageNumber: (json['sendMessageNumber'] as num?)?.toInt() ?? 0,
      receiveMessageNumber: (json['receiveMessageNumber'] as num?)?.toInt() ?? 0,
      theirPublicKey: json['theirPublicKey'] as String? ?? '',
      isInitiator: json['isInitiator'] as bool? ?? false,
    );
  }
}

/// Encrypted message structure (simplified)
class EncryptedMessage {
  final String ciphertext;
  final String nonce;
  final String authTag;
  final MessageHeader header;

  EncryptedMessage({
    required this.ciphertext,
    required this.nonce,
    required this.authTag,
    required this.header,
  });

  Map<String, dynamic> toJson() {
    return {
      'ciphertext': ciphertext,
      'nonce': nonce,
      'authTag': authTag,
      'header': header.toJson(),
    };
  }

  factory EncryptedMessage.fromJson(Map<String, dynamic> json) {
    return EncryptedMessage(
      ciphertext: json['ciphertext'] as String,
      nonce: json['nonce'] as String,
      authTag: json['authTag'] as String,
      header: MessageHeader.fromJson(json['header'] as Map<String, dynamic>),
    );
  }
}

/// Message header (simplified)
class MessageHeader {
  final String senderId;
  final int messageNumber;
  final String sessionId;

  MessageHeader({
    required this.senderId,
    required this.messageNumber,
    required this.sessionId,
  });

  Map<String, dynamic> toJson() {
    return {
      'senderId': senderId,
      'messageNumber': messageNumber,
      'sessionId': sessionId,
    };
  }

  factory MessageHeader.fromJson(Map<String, dynamic> json) {
    return MessageHeader(
      senderId: json['senderId'] as String,
      messageNumber: (json['messageNumber'] as num).toInt(),
      sessionId: json['sessionId'] as String,
    );
  }
}

/// Encryption result
class EncryptionResult {
  final String ciphertext;
  final String nonce;
  final String authTag;

  EncryptionResult({
    required this.ciphertext,
    required this.nonce,
    required this.authTag,
  });
}