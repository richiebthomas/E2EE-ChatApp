import 'user.dart';
import 'message.dart';

class Conversation {
  final User otherUser;
  final Message? lastMessage;
  final int unreadCount;
  final DateTime lastActivity;

  const Conversation({
    required this.otherUser,
    this.lastMessage,
    required this.unreadCount,
    required this.lastActivity,
  });

  factory Conversation.fromJson(Map<String, dynamic> json, String currentUserId) {
    final lastMessageJson = json['lastMessage'] as Map<String, dynamic>?;
    
    return Conversation(
      otherUser: User.fromJson(json['otherUser'] as Map<String, dynamic>),
      lastMessage: lastMessageJson != null
          ? Message.fromJson(lastMessageJson, currentUserId)
          : null,
      unreadCount: json['unreadCount'] as int? ?? 0,
      lastActivity: lastMessageJson != null
          ? DateTime.parse(lastMessageJson['createdAt'] as String)
          : DateTime.now(),
    );
  }

  String get displayText {
    if (lastMessage == null) {
      return 'No messages yet';
    }

    final message = lastMessage!;
    
    // For encrypted messages, show placeholder text
    if (message.plaintext != null && message.plaintext!.isNotEmpty) {
      return message.plaintext!;
    }
    
    // Show message type indicators
    switch (message.type) {
      case MessageType.keyExchange:
        return '🔐 Key exchange';
      case MessageType.prekeyRequest:
        return '🔑 Prekey request';
      case MessageType.regular:
        return '🔒 Encrypted message';
    }
  }

  String get timeDisplay {
    final now = DateTime.now();
    final difference = now.difference(lastActivity);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  Conversation copyWith({
    User? otherUser,
    Message? lastMessage,
    int? unreadCount,
    DateTime? lastActivity,
  }) {
    return Conversation(
      otherUser: otherUser ?? this.otherUser,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      lastActivity: lastActivity ?? this.lastActivity,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Conversation && other.otherUser.id == otherUser.id;
  }

  @override
  int get hashCode => otherUser.id.hashCode;

  @override
  String toString() {
    return 'Conversation(user: ${otherUser.username}, unread: $unreadCount)';
  }
}
