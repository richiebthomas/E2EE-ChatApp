enum MessageType {
  regular,
  keyExchange,
  prekeyRequest,
}

enum MessageStatus {
  sending,
  sent,
  delivered,
  acknowledged,
  failed,
}

class Message {
  final String id;
  final String senderId;
  final String recipientId;
  final String ciphertext;
  final String? plaintext; // Decrypted content (not stored)
  final MessageType type;
  final MessageStatus status;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? acknowledgedAt;
  final bool isFromMe;

  const Message({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.ciphertext,
    this.plaintext,
    required this.type,
    required this.status,
    required this.createdAt,
    this.deliveredAt,
    this.acknowledgedAt,
    required this.isFromMe,
  });

  factory Message.fromJson(Map<String, dynamic> json, String currentUserId) {
    return Message(
      id: json['id'] as String? ?? 'unknown',
      senderId: json['senderId'] as String? ?? '',
      recipientId: json['recipientId'] as String? ?? '',
      ciphertext: json['ciphertext'] as String? ?? '',
      type: _parseMessageType(json['messageType'] as String?),
      status: _parseMessageStatus(json),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      deliveredAt: json['deliveredAt'] != null
          ? DateTime.parse(json['deliveredAt'] as String)
          : null,
      acknowledgedAt: json['acknowledgedAt'] != null
          ? DateTime.parse(json['acknowledgedAt'] as String)
          : null,
      isFromMe: (json['senderId'] as String?) == currentUserId,
    );
  }

  static MessageType _parseMessageType(String? type) {
    switch (type?.toUpperCase()) {
      case 'KEY_EXCHANGE':
        return MessageType.keyExchange;
      case 'PREKEY_REQUEST':
        return MessageType.prekeyRequest;
      default:
        return MessageType.regular;
    }
  }

  static MessageStatus _parseMessageStatus(Map<String, dynamic> json) {
    if (json['acknowledged'] == true) {
      return MessageStatus.acknowledged;
    } else if (json['delivered'] == true) {
      return MessageStatus.delivered;
    } else {
      return MessageStatus.sent;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'recipientId': recipientId,
      'ciphertext': ciphertext,
      'messageType': _messageTypeToString(type),
      'createdAt': createdAt.toIso8601String(),
      'deliveredAt': deliveredAt?.toIso8601String(),
      'acknowledgedAt': acknowledgedAt?.toIso8601String(),
    };
  }

  String _messageTypeToString(MessageType type) {
    switch (type) {
      case MessageType.keyExchange:
        return 'KEY_EXCHANGE';
      case MessageType.prekeyRequest:
        return 'PREKEY_REQUEST';
      case MessageType.regular:
        return 'REGULAR';
    }
  }

  Message copyWith({
    String? id,
    String? senderId,
    String? recipientId,
    String? ciphertext,
    String? plaintext,
    MessageType? type,
    MessageStatus? status,
    DateTime? createdAt,
    DateTime? deliveredAt,
    DateTime? acknowledgedAt,
    bool? isFromMe,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      recipientId: recipientId ?? this.recipientId,
      ciphertext: ciphertext ?? this.ciphertext,
      plaintext: plaintext ?? this.plaintext,
      type: type ?? this.type,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      isFromMe: isFromMe ?? this.isFromMe,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Message && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Message(id: $id, senderId: $senderId, type: $type, status: $status)';
  }
}
