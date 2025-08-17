import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/message.dart';

enum SocketStatus {
  connecting,
  connected,
  disconnected,
  error,
}

class SocketService extends ChangeNotifier {
  IO.Socket? _socket;
  SocketStatus _status = SocketStatus.disconnected;
  String? _errorMessage;

  // Event handlers
  Function(Message)? onNewMessage;
  Function(String, String, bool)? onUserTyping; // userId, username, typing
  Function(String, String)? onUserStatusChanged; // userId, status
  Function(String, DateTime)? onMessageDelivered; // messageId, deliveredAt
  Function(String, DateTime, String)? onMessageAcknowledged; // messageId, acknowledgedAt, acknowledgedBy

  // Getters
  SocketStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _status == SocketStatus.connected;

  // Connect to server
  Future<void> connect({
    required String serverUrl,
    required String authToken,
  }) async {
    try {
      _setStatus(SocketStatus.connecting);

      _socket = IO.io(
        serverUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .setAuth({'token': authToken})
            .enableAutoConnect()
            .build(),
      );

      _setupEventListeners();
      
    } catch (e) {
      _setError('Failed to connect: $e');
    }
  }

  // Disconnect from server
  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _setStatus(SocketStatus.disconnected);
  }

  // Setup event listeners
  void _setupEventListeners() {
    if (_socket == null) return;

    // Connection events
    _socket!.onConnect((_) {
      debugPrint('🔌 Socket connected');
      _setStatus(SocketStatus.connected);
    });

    _socket!.onDisconnect((_) {
      debugPrint('🔌 Socket disconnected');
      _setStatus(SocketStatus.disconnected);
    });

    _socket!.onError((error) {
      debugPrint('🔌 Socket error: $error');
      _setError('Connection error: $error');
    });

    _socket!.onConnectError((error) {
      debugPrint('🔌 Socket connection error: $error');
      _setError('Connection failed: $error');
    });

    // Chat events
    _socket!.on('connected', (data) {
      debugPrint('🔌 Connected to server: $data');
    });

    _socket!.on('new_message', (data) {
      debugPrint('📨 New message received: $data');
      try {
        final message = Message.fromJson(data as Map<String, dynamic>, ''); // currentUserId will be set by the handler
        onNewMessage?.call(message);
      } catch (e) {
        debugPrint('Error parsing new message: $e');
      }
    });

    _socket!.on('user_typing', (data) {
      debugPrint('⌨️ User typing: $data');
      try {
        final userId = data['userId'] as String;
        final username = data['username'] as String;
        final typing = data['typing'] as bool;
        onUserTyping?.call(userId, username, typing);
      } catch (e) {
        debugPrint('Error parsing typing indicator: $e');
      }
    });

    _socket!.on('user_status_changed', (data) {
      debugPrint('👤 User status changed: $data');
      try {
        final userId = data['userId'] as String;
        final status = data['status'] as String;
        onUserStatusChanged?.call(userId, status);
      } catch (e) {
        debugPrint('Error parsing status change: $e');
      }
    });

    _socket!.on('message_delivered', (data) {
      debugPrint('✅ Message delivered: $data');
      try {
        final messageId = data['messageId'] as String;
        final deliveredAt = DateTime.parse(data['deliveredAt'] as String);
        onMessageDelivered?.call(messageId, deliveredAt);
      } catch (e) {
        debugPrint('Error parsing delivery confirmation: $e');
      }
    });

    _socket!.on('message_acknowledged', (data) {
      debugPrint('✅ Message acknowledged: $data');
      try {
        final messageId = data['messageId'] as String;
        final acknowledgedAt = DateTime.parse(data['acknowledgedAt'] as String);
        final acknowledgedBy = data['acknowledgedBy'] as String;
        onMessageAcknowledged?.call(messageId, acknowledgedAt, acknowledgedBy);
      } catch (e) {
        debugPrint('Error parsing acknowledgment: $e');
      }
    });

    _socket!.on('error', (data) {
      debugPrint('❌ Server error: $data');
      _setError('Server error: $data');
    });
  }

  // Send typing indicator
  void sendTypingStart(String recipientId) {
    if (!isConnected) return;
    
    _socket?.emit('typing_start', {
      'recipientId': recipientId,
    });
  }

  void sendTypingStop(String recipientId) {
    if (!isConnected) return;
    
    _socket?.emit('typing_stop', {
      'recipientId': recipientId,
    });
  }

  // Update user status
  void updateStatus(String status) {
    if (!isConnected) return;
    
    _socket?.emit('status_update', {
      'status': status,
    });
  }

  // Confirm message delivery
  void confirmMessageDelivery(String messageId) {
    if (!isConnected) return;
    
    _socket?.emit('message_delivered', {
      'messageId': messageId,
    });
  }

  // Set status and notify listeners
  void _setStatus(SocketStatus newStatus) {
    _status = newStatus;
    if (newStatus != SocketStatus.error) {
      _errorMessage = null;
    }
    notifyListeners();
  }

  // Set error status
  void _setError(String message) {
    _errorMessage = message;
    _status = SocketStatus.error;
    notifyListeners();
  }

  // Clear error
  void clearError() {
    if (_status == SocketStatus.error) {
      _setStatus(SocketStatus.disconnected);
    }
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
