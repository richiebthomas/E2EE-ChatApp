import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/user.dart';

import '../../../services/message_service.dart';
import '../../../services/socket_service.dart';
import '../../../utils/constants.dart';
import '../../../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  final User otherUser;

  const ChatScreen({
    Key? key,
    required this.otherUser,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;
  bool _isTyping = false;
  String? _typingUser;

  @override
  void initState() {
    super.initState();
    _loadConversation();
    _setupTypingListener();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadConversation() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final messageService = context.read<MessageService>();
      await messageService.loadConversation(widget.otherUser.id);
      
      setState(() {
        _isLoading = false;
      });

      // Scroll to bottom after loading
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
      
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _setupTypingListener() {
    final socketService = context.read<SocketService>();
    socketService.onUserTyping = (userId, username, typing) {
      if (userId == widget.otherUser.id) {
        setState(() {
          _isTyping = typing;
          _typingUser = typing ? username : null;
        });
        
        // Auto-hide typing indicator after 3 seconds
        if (typing) {
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted && _isTyping) {
              setState(() {
                _isTyping = false;
                _typingUser = null;
              });
            }
          });
        }
      }
    };
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    try {
      setState(() {
        _isSending = true;
      });

      final messageService = context.read<MessageService>();
      await messageService.sendMessage(
        recipientId: widget.otherUser.id,
        plaintext: text,
      );

      _messageController.clear();
      _scrollToBottom();
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message: $e'),
          backgroundColor: AppConstants.errorColor,
        ),
      );
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: AppConstants.shortAnimation,
        curve: Curves.easeOut,
      );
    }
  }

  void _onMessageChanged(String text) {
    final messageService = context.read<MessageService>();
    
    if (text.trim().isNotEmpty) {
      messageService.sendTypingStart(widget.otherUser.id);
    } else {
      messageService.sendTypingStop(widget.otherUser.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text(
                widget.otherUser.username.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: AppConstants.defaultPadding),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherUser.username,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_isTyping && _typingUser != null)
                    Text(
                      'typing...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else
                    Row(
                      children: [
                        Icon(
                          Icons.lock,
                          size: 12,
                          color: AppConstants.encryptedColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Encrypted',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppConstants.encryptedColor,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'verify':
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Key verification coming soon!')),
                  );
                  break;
                case 'clear':
                  _showClearChatDialog();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'verify',
                child: ListTile(
                  leading: Icon(Icons.verified_user),
                  title: Text('Verify Keys'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.clear_all),
                  title: Text('Clear Chat'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Encryption status banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.defaultPadding,
              vertical: AppConstants.smallPadding,
            ),
            color: AppConstants.encryptedColor.withOpacity(0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.security,
                  size: 16,
                  color: AppConstants.encryptedColor,
                ),
                const SizedBox(width: AppConstants.smallPadding),
                Text(
                  AppConstants.encryptionEnabledMessage,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppConstants.encryptedColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          
          // Messages area
          Expanded(
            child: _buildMessagesArea(),
          ),
          
          // Message input
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessagesArea() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: AppConstants.defaultPadding),
            Text('Loading conversation...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: AppConstants.defaultPadding),
            Text(
              'Failed to load conversation',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppConstants.smallPadding),
            Text(
              _errorMessage!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.defaultPadding),
            ElevatedButton(
              onPressed: _loadConversation,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Consumer<MessageService>(
      builder: (context, messageService, child) {
        final messages = messageService.getConversation(widget.otherUser.id);
        
        if (messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: AppConstants.defaultPadding),
                Text(
                  'No messages yet',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppConstants.smallPadding),
                Text(
                  'Send a message to start the conversation',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.defaultPadding,
            vertical: AppConstants.smallPadding,
          ),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            return MessageBubble(
              message: message,
              isFromMe: message.isFromMe,
            );
          },
        );
      },
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.defaultPadding,
                  vertical: AppConstants.smallPadding,
                ),
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              onChanged: _onMessageChanged,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: AppConstants.smallPadding),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: _isSending ? null : _sendMessage,
              icon: _isSending
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : Icon(
                      Icons.send,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showClearChatDialog() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat'),
        content: const Text('Are you sure you want to clear all messages in this conversation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (shouldClear == true) {
      final messageService = context.read<MessageService>();
      messageService.clearConversation(widget.otherUser.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat history cleared')),
      );
    }
  }
}
