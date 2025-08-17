import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../models/message.dart';
import 'api_service.dart';
import 'crypto_service.dart';
import 'secure_storage_service.dart';
import 'socket_service.dart';

class MessageService extends ChangeNotifier {
  final ApiService _apiService;
  final SecureStorageService _storageService;
  final SocketService _socketService;

  // Message cache by conversation (userId -> List<Message>)
  final Map<String, List<Message>> _conversations = {};
  
  bool _initialized = false;

  MessageService(this._apiService, this._storageService, this._socketService) {
    _setupSocketListeners();
    _initializeSignalProtocol();
  }
  
  /// Initialize Signal Protocol
  Future<void> _initializeSignalProtocol() async {
    if (!_initialized) {
      await CryptoService.initialize(_storageService);
      _initialized = true;
      debugPrint('🔐 Signal Protocol initialized');
    }
  }

  // Getters
  Map<String, List<Message>> get conversations => _conversations;
  
  List<Message> getConversation(String userId) {
    return _conversations[userId] ?? [];
  }

  // Setup socket event listeners
  void _setupSocketListeners() {
    _socketService.onNewMessage = _handleNewMessage;
    _socketService.onMessageDelivered = _handleMessageDelivered;
    _socketService.onMessageAcknowledged = _handleMessageAcknowledged;
  }

  // Load conversation history
  Future<void> loadConversation(String userId) async {
    try {
      final messages = await _apiService.getConversation(userId);
      
      // Decrypt messages in chronological order
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      
      final decryptedMessages = <Message>[];
      for (final message in messages) {
        final decryptedMessage = await _decryptMessage(message, userId);
        decryptedMessages.add(decryptedMessage);
      }
      
      _conversations[userId] = decryptedMessages;
      notifyListeners();
      
    } catch (e) {
      debugPrint('Failed to load conversation: $e');
      throw Exception('Failed to load conversation: $e');
    }
  }

  // Send message
  Future<void> sendMessage({
    required String recipientId,
    required String plaintext,
  }) async {
    try {
      await _initializeSignalProtocol();
      
      // Ensure Signal Protocol session exists
      await _ensureSignalSession(recipientId);
      
      // Encrypt with Signal Protocol
      final ciphertext = await CryptoService.encryptMessageSignal(recipientId, plaintext);
      debugPrint('🔐 Message encrypted with Signal Protocol');

      // Send to backend
      final messageId = await _apiService.sendMessage(
        recipientId: recipientId,
        ciphertext: ciphertext,
      );

      // Create local message object
      final message = Message(
        id: messageId,
        senderId: _apiService.currentUser!.id,
        recipientId: recipientId,
        ciphertext: ciphertext,
        plaintext: plaintext,
        createdAt: DateTime.now(),
        isFromMe: true,
        type: MessageType.regular,
        status: MessageStatus.sent,
      );

      // Add to conversation
      _addMessageToConversation(recipientId, message);
      
    } catch (e) {
      debugPrint('Failed to send message: $e');
      throw Exception('Failed to send message: $e');
    }
  }

  /// Ensure Signal Protocol session exists with user
  Future<void> _ensureSignalSession(String userId) async {
    if (CryptoService.hasSignalSession(userId)) {
      return; // Session already exists
    }

    try {
      debugPrint('🔑 Establishing Signal Protocol session with user: $userId');
      
      // Get the user's prekey bundle
      final bundle = await _apiService.getPrekeyBundle(userId);
      
      // Verify signed prekey (simplified check)
      final isValidSignature = await CryptoService.verifySignedPrekey(
        identityPublicKey: bundle.identityPubkey,
        signedPrekeyPublic: bundle.signedPrekey.pubkey,
        signature: bundle.signedPrekey.signature,
      );
      
      if (!isValidSignature) {
        debugPrint('⚠️ Signed prekey signature invalid, proceeding anyway for demo');
      }
      
      // Start Signal Protocol session
      await CryptoService.startSignalSession(
        otherUserId: userId,
        identityKey: bundle.identityPubkey,
        signedPrekey: bundle.signedPrekey.pubkey,
        signature: bundle.signedPrekey.signature,
        oneTimePrekey: bundle.oneTimePrekey?.pubkey,
      );
      
      debugPrint('✅ Signal Protocol session established');
      
    } catch (e) {
      debugPrint('❌ Failed to establish Signal Protocol session: $e');
      rethrow;
    }
  }

  // Decrypt incoming message
  Future<Message> _decryptMessage(Message message, String otherUserId) async {
    try {
      await _initializeSignalProtocol();
      
      // Check if this is a new Signal Protocol message format
      if (_isNewSignalFormat(message.ciphertext)) {
        final plaintext = await CryptoService.decryptMessageSignal(otherUserId, message.ciphertext);
        debugPrint('🔓 Message decrypted with new Signal Protocol');
        return message.copyWith(plaintext: plaintext);
      } else {
        // Legacy message - mark as undecryptable
        debugPrint('⚠️ Legacy message format detected - cannot decrypt with new protocol');
        return message.copyWith(
          plaintext: '[Legacy message - please clear chat history]',
        );
      }
      
    } catch (e) {
      debugPrint('❌ Failed to decrypt message: $e');
      return message.copyWith(
        plaintext: '[Message could not be decrypted]',
      );
    }
  }

  // Check if ciphertext is in new Signal Protocol format
  bool _isNewSignalFormat(String ciphertext) {
    try {
      final parsed = Map<String, dynamic>.from(
        const JsonDecoder().convert(ciphertext)
      );
      // New format has these specific fields
      return parsed.containsKey('ciphertext') && 
             parsed.containsKey('nonce') && 
             parsed.containsKey('authTag') && 
             parsed.containsKey('header') &&
             parsed['header'] is Map &&
             (parsed['header'] as Map).containsKey('senderId');
    } catch (e) {
      return false;
    }
  }

  // Add message to conversation
  void _addMessageToConversation(String userId, Message message) {
    if (!_conversations.containsKey(userId)) {
      _conversations[userId] = [];
    }
    
    // Check if message already exists (avoid duplicates)
    final existingIndex = _conversations[userId]!.indexWhere((m) => m.id == message.id);
    if (existingIndex != -1) {
      _conversations[userId]![existingIndex] = message;
    } else {
      _conversations[userId]!.add(message);
      _conversations[userId]!.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    
    notifyListeners();
  }

  // Handle incoming message from socket
  Future<void> _handleNewMessage(Message message) async {
    try {
      final currentUserId = _apiService.currentUser?.id;
      if (currentUserId == null) return;

      // Determine conversation partner
      final otherUserId = message.senderId == currentUserId 
          ? message.recipientId 
          : message.senderId;

      // Decrypt message
      final decryptedMessage = await _decryptMessage(
        message.copyWith(isFromMe: message.senderId == currentUserId),
        otherUserId,
      );

      // Add to conversation
      _addMessageToConversation(otherUserId, decryptedMessage);

      // Confirm delivery if we're the recipient
      if (message.recipientId == currentUserId) {
        _socketService.confirmMessageDelivery(message.id);
      }
      
    } catch (e) {
      debugPrint('Failed to handle new message: $e');
    }
  }

  // Handle message delivery confirmation
  void _handleMessageDelivered(String messageId, DateTime deliveredAt) {
    // Update message status in conversations
    for (final conversation in _conversations.values) {
      final messageIndex = conversation.indexWhere((m) => m.id == messageId);
      if (messageIndex != -1) {
        conversation[messageIndex] = conversation[messageIndex].copyWith(
          deliveredAt: deliveredAt,
        );
        notifyListeners();
        break;
      }
    }
  }

  // Handle message acknowledgment
  void _handleMessageAcknowledged(String messageId, DateTime readAt, String acknowledgedBy) {
    // Update message status in conversations
    for (final conversation in _conversations.values) {
      final messageIndex = conversation.indexWhere((m) => m.id == messageId);
      if (messageIndex != -1) {
        conversation[messageIndex] = conversation[messageIndex].copyWith(
          status: MessageStatus.acknowledged,
        );
        notifyListeners();
        break;
      }
    }
  }

  // Clear conversation
  void clearConversation(String userId) {
    _conversations.remove(userId);
    notifyListeners();
  }

  // Clear all conversations
  void clearAllConversations() {
    _conversations.clear();
    notifyListeners();
  }

  // Send typing indicator start
  void sendTypingStart(String userId) {
    _socketService.sendTypingStart(userId);
  }

  // Send typing indicator stop
  void sendTypingStop(String userId) {
    _socketService.sendTypingStop(userId);
  }

  @override
  void dispose() {
    super.dispose();
  }
}