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
    int? oneTimePrekeyId,
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
        usedOneTimePrekeyId: oneTimePrekeyId,
      );
      
      _sessions[otherUserId] = session;
      await _saveSession(session);
      
      print('✅ Session created successfully (initiator) user=$otherUserId sess=${session.sessionId.substring(0,8)} otp=${oneTimePrekeyId ?? -1}');
      return session;
      
    } catch (e) {
      print('❌ Failed to start session: $e');
      rethrow;
    }
  }

  /// Start session from incoming message (receiver side)
  Future<SignalSession> startSessionFromIncoming({
    required String otherUserId,
    required String senderEphemeralKey,
    required String senderIdentityKey,
    int? oneTimePrekeyId,
  }) async {
    try {
      print('🔑 Starting session from incoming message');
      
      // Get our keys
      final ourKeys = await _getOurKeys();
      
      // Perform X3DH as receiver (optionally include our one-time prekey if specified)
      final sharedSecret = await _performX3DHReceiver(
        ourKeys: ourKeys,
        theirIdentityKey: senderIdentityKey,
        theirEphemeralKey: senderEphemeralKey,
        ourOneTimePrekeyId: oneTimePrekeyId,
      );
      
      // Create session
      final session = await _createSession(
        otherUserId: otherUserId,
        sharedSecret: sharedSecret,
        ourKeys: ourKeys,
        theirSignedPrekey: senderEphemeralKey,
        isInitiator: false,
        usedOneTimePrekeyId: oneTimePrekeyId,
      );
      
      _sessions[otherUserId] = session;
      await _saveSession(session);
      
      print('✅ Session created from incoming message user=$otherUserId sess=${session.sessionId.substring(0,8)} otp=${oneTimePrekeyId ?? -1}');
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
      
      // Build header (used as AAD for AEAD)
      final header = MessageHeader(
        senderId: await _getCurrentUserId(),
        messageNumber: messageNumber,
        sessionId: session.sessionId,
        senderIdentityKey: session.ourIdentityPublic,
        senderEphemeralKey: session.ourEphemeralPublic,
        receiverOneTimePrekeyId: session.usedOneTimePrekeyId,
        isPrekeyMessage: session.isInitiator && messageNumber == 0,
        version: 'v1',
      );
      final aadBytes = _aadForHeader(header);

      // Derive direction key from root + senderId, then derive per-message key
      final directionKey = await _deriveDirectionKey(
        rootKeyBase64: session.rootKey,
        sessionId: session.sessionId,
        senderId: header.senderId,
      );
      final messageKey = await _deriveMessageKey(
        baseKeyBytes: directionKey,
        messageNumber: messageNumber,
        sessionId: session.sessionId,
      );
      print('🔑 Keys: rootFp=${await _fp(base64Decode(session.rootKey))} dirFp=${await _fp(directionKey)} msg#=$messageNumber aad="${String.fromCharCodes(aadBytes)}"');
      
      // Encrypt the message
      final encryptedData = await _encryptWithKey(
        messageKey,
        plaintext,
        aad: aadBytes,
      );
      
      // Create message
      final message = EncryptedMessage(
        ciphertext: encryptedData.ciphertext,
        nonce: encryptedData.nonce,
        authTag: encryptedData.authTag,
        header: header,
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
    Future<String> _attemptDecrypt(SignalSession session) async {
      final messageNumber = encryptedMessage.header.messageNumber;
      final directionKey = await _deriveDirectionKey(
        rootKeyBase64: session.rootKey,
        sessionId: session.sessionId,
        senderId: encryptedMessage.header.senderId,
      );
      final messageKey = await _deriveMessageKey(
        baseKeyBytes: directionKey,
        messageNumber: messageNumber,
        sessionId: session.sessionId,
      );
      // Print keys before decryption so we still get diagnostics on MAC failures
      print('🧪 Decrypt attempt keys: rootFp=${await _fp(base64Decode(session.rootKey))} dirFp=${await _fp(directionKey)} msg#=$messageNumber aad="${String.fromCharCodes(_aadForHeader(encryptedMessage.header))}"');
      final plaintext = await _decryptWithKey(
        messageKey,
        encryptedMessage.ciphertext,
        encryptedMessage.nonce,
        encryptedMessage.authTag,
        aad: _aadForHeader(encryptedMessage.header),
      );
      print('🔑 Decrypt keys: rootFp=${await _fp(base64Decode(session.rootKey))} dirFp=${await _fp(directionKey)} msg#=$messageNumber aad="${String.fromCharCodes(_aadForHeader(encryptedMessage.header))}"');
      // Update receive counter if it's not our own message
      final currentUserId = await _getCurrentUserId();
      final isOwnMessage = encryptedMessage.header.senderId == currentUserId;
      if (!isOwnMessage && messageNumber >= session.receiveMessageNumber) {
        session.receiveMessageNumber = messageNumber + 1;
        await _saveSession(session);
      }
      print('🔓 Message decrypted (msg #$messageNumber)');
      return plaintext;
    }

    var session = _sessions[userId];

    // Determine if this is our own message
    final currentUserId = await _getCurrentUserId();
    final isOwnMessage = encryptedMessage.header.senderId == currentUserId;

    // If no session and it's NOT our own message, try to create one from the incoming header
    if (session == null && !isOwnMessage) {
      print('📥 No session found, creating from incoming message');
      session = await startSessionFromIncoming(
        otherUserId: userId,
        senderEphemeralKey: encryptedMessage.header.senderEphemeralKey,
        senderIdentityKey: encryptedMessage.header.senderIdentityKey,
        oneTimePrekeyId: encryptedMessage.header.receiverOneTimePrekeyId,
      );
    }

    if (session == null) {
      // We cannot reconstruct a session for our own previously sent messages without stored session state
      throw Exception('Missing session for user $userId');
    }

    try {
      return await _attemptDecrypt(session);
    } catch (e) {
      final errorStr = e.toString();
      if (!isOwnMessage && (errorStr.contains('SecretBoxAuthenticationError') || errorStr.contains('MAC'))) {
        print('🔁 MAC failed, rebuilding session from header and retrying...');
        session = await startSessionFromIncoming(
          otherUserId: userId,
          senderEphemeralKey: encryptedMessage.header.senderEphemeralKey,
          senderIdentityKey: encryptedMessage.header.senderIdentityKey,
          oneTimePrekeyId: encryptedMessage.header.receiverOneTimePrekeyId,
        );
        try {
          return await _attemptDecrypt(session);
        } catch (_) {
          // Compatibility fallback 1: old key schedule (send/receive keys) + canonical AAD
          try {
            final messageNumber = encryptedMessage.header.messageNumber;
            final currentUserId = await _getCurrentUserId();
            final isOwn = encryptedMessage.header.senderId == currentUserId;
            final legacyBaseKey = isOwn ? session.sendKey : session.receiveKey;
            final legacyKey = await _deriveLegacyMessageKey(
              baseKeyBase64: legacyBaseKey,
              messageNumber: messageNumber,
              otherUserId: session.userId,
              isOutgoing: isOwn,
            );
            return await _decryptWithKey(
              legacyKey,
              encryptedMessage.ciphertext,
              encryptedMessage.nonce,
              encryptedMessage.authTag,
              aad: _aadForHeader(encryptedMessage.header),
            );
          } catch (_) {
            // Compatibility fallback 2: legacy JSON AAD
            final messageNumber = encryptedMessage.header.messageNumber;
            final currentUserId = await _getCurrentUserId();
            final isOwn = encryptedMessage.header.senderId == currentUserId;
            final legacyBaseKey = isOwn ? session.sendKey : session.receiveKey;
            final legacyKey = await _deriveLegacyMessageKey(
              baseKeyBase64: legacyBaseKey,
              messageNumber: messageNumber,
              otherUserId: session.userId,
              isOutgoing: isOwn,
            );
            try {
              return await _decryptWithKey(
                legacyKey,
                encryptedMessage.ciphertext,
                encryptedMessage.nonce,
                encryptedMessage.authTag,
                aad: utf8.encode(jsonEncode(encryptedMessage.header.toJson())),
              );
            } catch (_) {
              // Compatibility fallback 3: no AAD (very old builds)
              return await _decryptWithKey(
                legacyKey,
                encryptedMessage.ciphertext,
                encryptedMessage.nonce,
                encryptedMessage.authTag,
              );
            }
          }
        }
      }
      print('❌ Failed to decrypt message: $e');
      rethrow;
    }
  }

  /// Old message-key derivation used in earlier builds
  Future<String> _deriveLegacyMessageKey({
    required String baseKeyBase64,
    required int messageNumber,
    required String otherUserId,
    required bool isOutgoing,
  }) async {
    final info = 'MessageKey_${otherUserId}_${isOutgoing ? 'out' : 'in'}_$messageNumber';
    final keyBytes = await _hkdf(base64Decode(baseKeyBase64), info, 32);
    return base64Encode(keyBytes);
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
    final combinedBytes = Uint8List.fromList(combined);
    print('🔧 X3DH initiator: usedOTP=${theirOneTimePrekey != null} combinedFp=${await _fp(combinedBytes)} len=${combinedBytes.length}');
    return combinedBytes;
  }

  /// Perform X3DH as receiver (optionally include our one-time prekey by ID)
  Future<Uint8List> _performX3DHReceiver({
    required UserKeys ourKeys,
    required String theirIdentityKey,
    required String theirEphemeralKey,
    int? ourOneTimePrekeyId,
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

    // Optionally include DH4 using our one-time prekey if provided
    if (ourOneTimePrekeyId != null) {
      final otpPrivate = await _storage.getOneTimePrekeyPrivate(ourOneTimePrekeyId);
      if (otpPrivate != null && otpPrivate.isNotEmpty) {
        final ourOneTimePrekeyPair = await _x25519.newKeyPairFromSeed(
          base64Decode(otpPrivate),
        );
        final dh4 = await _x25519.sharedSecretKey(
          keyPair: ourOneTimePrekeyPair,
          remotePublicKey: theirEphemeralPublic,
        );
        combined.addAll(await dh4.extractBytes());
        // Consume local one-time prekey after use
        await _storage.deleteOneTimePrekeyPrivate(ourOneTimePrekeyId);
      }
    }
    final combinedBytes = Uint8List.fromList(combined);
    print('🔧 X3DH receiver: usedOTP=${ourOneTimePrekeyId != null} otpId=${ourOneTimePrekeyId ?? -1} combinedFp=${await _fp(combinedBytes)} len=${combinedBytes.length}');
    return combinedBytes;
  }

  /// Create a session with deterministic key assignment
  Future<SignalSession> _createSession({
    required String otherUserId,
    required Uint8List sharedSecret,
    required UserKeys ourKeys,
    required String theirSignedPrekey,
    required bool isInitiator,
    int? usedOneTimePrekeyId,
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
    
    // Extract our public keys for header binding
    final ourIdentityPublicKey = await ourKeys.identityKeyPair.extractPublicKey() as SimplePublicKey;
    final ourEphemeralPublicKey = await ourKeys.ephemeralKeyPair.extractPublicKey() as SimplePublicKey;

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
      ourIdentityPublic: base64Encode(ourIdentityPublicKey.bytes),
      ourEphemeralPublic: base64Encode(ourEphemeralPublicKey.bytes),
      usedOneTimePrekeyId: usedOneTimePrekeyId,
    );
  }

  /// Derive a direction key from the session root key and senderId
  Future<Uint8List> _deriveDirectionKey({
    required String rootKeyBase64,
    required String sessionId,
    required String senderId,
  }) async {
    final info = 'DirKey_${sessionId}_$senderId';
    return await _hkdf(base64Decode(rootKeyBase64), info, 32);
  }

  /// Derive message key deterministically (same on both sides)
  Future<String> _deriveMessageKey({
    required Uint8List baseKeyBytes,
    required int messageNumber,
    required String sessionId,
  }) async {
    final info = 'MessageKey_${sessionId}_$messageNumber';
    final keyBytes = await _hkdf(baseKeyBytes, info, 32);
    return base64Encode(keyBytes);
  }

  /// Encrypt with authenticated encryption
  Future<EncryptionResult> _encryptWithKey(String messageKey, String plaintext, { List<int>? aad }) async {
    final keyBytes = base64Decode(messageKey);
    final secretKey = SecretKey(keyBytes);
    final plainData = utf8.encode(plaintext);
    
    final secretBox = await _aes.encrypt(
      plainData,
      secretKey: secretKey,
      aad: aad ?? const <int>[],
    );
    
    return EncryptionResult(
      ciphertext: base64Encode(secretBox.cipherText),
      nonce: base64Encode(secretBox.nonce),
      authTag: base64Encode(secretBox.mac.bytes),
    );
  }

  /// Decrypt with authenticated decryption
  Future<String> _decryptWithKey(String messageKey, String ciphertext, String nonce, String authTag, { List<int>? aad }) async {
    final keyBytes = base64Decode(messageKey);
    final secretKey = SecretKey(keyBytes);
    
    final secretBox = SecretBox(
      base64Decode(ciphertext),
      nonce: base64Decode(nonce),
      mac: Mac(base64Decode(authTag)),
    );
    
    final decryptedData = await _aes.decrypt(
      secretBox,
      secretKey: secretKey,
      aad: aad ?? const <int>[],
    );
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

  /// Build canonical AAD bytes from header to avoid JSON ordering/whitespace issues
  List<int> _aadForHeader(MessageHeader header) {
    final canonical = 'v=${header.version}|sid=${header.sessionId}|s=${header.senderId}|n=${header.messageNumber}|ik=${header.senderIdentityKey}|ek=${header.senderEphemeralKey}|otp=${header.receiverOneTimePrekeyId ?? -1}|p=${header.isPrekeyMessage ? 1 : 0}';
    return utf8.encode(canonical);
  }

  Future<String> _fp(Uint8List bytes) async {
    final digest = crypto.sha256.convert(bytes);
    return base64Encode(digest.bytes).substring(0, 8);
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
  final String ourIdentityPublic;
  final String ourEphemeralPublic;
  final int? usedOneTimePrekeyId;

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
    required this.ourIdentityPublic,
    required this.ourEphemeralPublic,
    this.usedOneTimePrekeyId,
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
      'ourIdentityPublic': ourIdentityPublic,
      'ourEphemeralPublic': ourEphemeralPublic,
      'usedOneTimePrekeyId': usedOneTimePrekeyId,
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
      ourIdentityPublic: json['ourIdentityPublic'] as String? ?? '',
      ourEphemeralPublic: json['ourEphemeralPublic'] as String? ?? '',
      usedOneTimePrekeyId: (json['usedOneTimePrekeyId'] as num?)?.toInt(),
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
  final String senderIdentityKey;
  final String senderEphemeralKey;
  final int? receiverOneTimePrekeyId;
  final bool isPrekeyMessage;
  final String version;

  MessageHeader({
    required this.senderId,
    required this.messageNumber,
    required this.sessionId,
    required this.senderIdentityKey,
    required this.senderEphemeralKey,
    required this.isPrekeyMessage,
    required this.version,
    this.receiverOneTimePrekeyId,
  });

  Map<String, dynamic> toJson() {
    return {
      'senderId': senderId,
      'messageNumber': messageNumber,
      'sessionId': sessionId,
      'senderIdentityKey': senderIdentityKey,
      'senderEphemeralKey': senderEphemeralKey,
      'receiverOneTimePrekeyId': receiverOneTimePrekeyId,
      'isPrekeyMessage': isPrekeyMessage,
      'version': version,
    };
  }

  factory MessageHeader.fromJson(Map<String, dynamic> json) {
    return MessageHeader(
      senderId: json['senderId'] as String,
      messageNumber: (json['messageNumber'] as num).toInt(),
      sessionId: json['sessionId'] as String,
      senderIdentityKey: json['senderIdentityKey'] as String? ?? '',
      senderEphemeralKey: json['senderEphemeralKey'] as String? ?? '',
      receiverOneTimePrekeyId: (json['receiverOneTimePrekeyId'] as num?)?.toInt(),
      isPrekeyMessage: json['isPrekeyMessage'] as bool? ?? false,
      version: json['version'] as String? ?? 'v1',
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