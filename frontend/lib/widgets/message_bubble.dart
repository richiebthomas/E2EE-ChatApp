import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';
import '../utils/constants.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isFromMe;

  const MessageBubble({
    Key? key,
    required this.message,
    required this.isFromMe,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isFromMe 
            ? MainAxisAlignment.end 
            : MainAxisAlignment.start,
        children: [
          if (!isFromMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text(
                'U', // You could pass the sender's initial here
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: AppConstants.smallPadding),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * AppConstants.messageBubbleMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: isFromMe 
                    ? CrossAxisAlignment.end 
                    : CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: AppConstants.messagePadding,
                    decoration: BoxDecoration(
                      color: _getBubbleColor(context),
                      borderRadius: BorderRadius.circular(
                        AppConstants.borderRadius,
                      ).copyWith(
                        bottomRight: isFromMe 
                            ? const Radius.circular(4) 
                            : null,
                        bottomLeft: !isFromMe 
                            ? const Radius.circular(4) 
                            : null,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildMessageContent(context),
                        if (message.type != MessageType.regular)
                          _buildMessageTypeIndicator(context),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildMessageStatus(context),
                ],
              ),
            ),
          ),
          if (isFromMe) ...[
            const SizedBox(width: AppConstants.smallPadding),
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(
                Icons.person,
                size: 16,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context) {
    switch (message.type) {
      case MessageType.keyExchange:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.key,
              size: 16,
              color: _getTextColor(context),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'Secure connection established',
                style: TextStyle(
                  color: _getTextColor(context),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        );
      
      case MessageType.prekeyRequest:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.security,
              size: 16,
              color: _getTextColor(context),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'Requesting encryption keys...',
                style: TextStyle(
                  color: _getTextColor(context),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        );
      
      case MessageType.regular:
      default:
        return Text(
          message.plaintext ?? '[Encrypted message]',
          style: TextStyle(
            color: _getTextColor(context),
            fontSize: 16,
          ),
        );
    }
  }

  Widget _buildMessageTypeIndicator(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock,
            size: 12,
            color: _getTextColor(context).withOpacity(0.7),
          ),
          const SizedBox(width: 4),
          Text(
            'System message',
            style: TextStyle(
              fontSize: 10,
              color: _getTextColor(context).withOpacity(0.7),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageStatus(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          DateFormat('HH:mm').format(message.createdAt),
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (isFromMe) ...[
          const SizedBox(width: 4),
          _buildStatusIcon(context),
        ],
        if (message.plaintext == null || message.plaintext!.startsWith('[Message could not be decrypted]')) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.warning,
            size: 12,
            color: AppConstants.warningColor,
          ),
        ],
      ],
    );
  }

  Widget _buildStatusIcon(BuildContext context) {
    switch (message.status) {
      case MessageStatus.sending:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
      
      case MessageStatus.sent:
        return Icon(
          Icons.check,
          size: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
      
      case MessageStatus.delivered:
        return Icon(
          Icons.done_all,
          size: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
      
      case MessageStatus.acknowledged:
        return Icon(
          Icons.done_all,
          size: 12,
          color: AppConstants.successColor,
        );
      
      case MessageStatus.failed:
        return Icon(
          Icons.error,
          size: 12,
          color: AppConstants.errorColor,
        );
    }
  }

  Color _getBubbleColor(BuildContext context) {
    if (isFromMe) {
      return Theme.of(context).colorScheme.primary;
    } else {
      return Theme.of(context).colorScheme.surfaceVariant;
    }
  }

  Color _getTextColor(BuildContext context) {
    if (isFromMe) {
      return Theme.of(context).colorScheme.onPrimary;
    } else {
      return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }
}
