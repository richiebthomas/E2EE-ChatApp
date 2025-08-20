const express = require('express');
const { PrismaClient } = require('@prisma/client');
const { body, validationResult, query } = require('express-validator');

const router = express.Router();
const prisma = new PrismaClient();

// Validation middleware
const validateMessage = [
  body('recipientId')
    .isUUID()
    .withMessage('Recipient ID must be a valid UUID'),
  body('ciphertext')
    .custom((value) => {
      // Accept either base64 string (legacy) or JSON object (Signal Protocol)
      if (typeof value === 'string') {
        // Legacy format - check if it's valid base64
        try {
          Buffer.from(value, 'base64');
          return true;
        } catch (e) {
          // Try parsing as JSON for Signal Protocol format
          try {
            const parsed = JSON.parse(value);
            if (parsed.ciphertext && parsed.header) {
              return true;
            }
          } catch (e) {
            // Not valid JSON either
          }
        }
      } else if (typeof value === 'object' && value.ciphertext && value.header) {
        // Direct object format
        return true;
      }
      throw new Error('Ciphertext must be valid base64 or Signal Protocol format');
    }),
  body('messageType')
    .optional()
    .isIn(['REGULAR', 'KEY_EXCHANGE', 'PREKEY_REQUEST'])
    .withMessage('Invalid message type')
];

const validateMessageQuery = [
  query('limit')
    .optional()
    .isInt({ min: 1, max: 100 })
    .withMessage('Limit must be between 1 and 100'),
  query('offset')
    .optional()
    .isInt({ min: 0 })
    .withMessage('Offset must be non-negative')
];

// Send encrypted message
router.post('/send', validateMessage, async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ 
        error: 'Validation failed', 
        details: errors.array() 
      });
    }

    const { recipientId, ciphertext, messageType = 'REGULAR' } = req.body;
    const senderId = req.user.id;

    // Verify recipient exists
    const recipient = await prisma.user.findUnique({
      where: { id: recipientId },
      select: { id: true, username: true }
    });

    if (!recipient) {
      return res.status(404).json({ error: 'Recipient not found' });
    }

    // Prevent sending to self
    if (senderId === recipientId) {
      return res.status(400).json({ error: 'Cannot send message to yourself' });
    }

    // Create message
    const message = await prisma.message.create({
      data: {
        senderId,
        recipientId,
        ciphertext,
        messageType
      },
      include: {
        sender: {
          select: {
            id: true,
            username: true
          }
        },
        recipient: {
          select: {
            id: true,
            username: true
          }
        }
      }
    });

    // Emit message via Socket.IO (if recipient is online)
    const io = req.app.get('io');
    if (io) {
      io.to(`user_${recipientId}`).emit('new_message', {
        id: message.id,
        senderId: message.senderId,
        senderUsername: message.sender.username,
        recipientId: message.recipientId,
        ciphertext: message.ciphertext,
        messageType: message.messageType,
        createdAt: message.createdAt
      });
    }

    res.status(201).json({
      message: 'Message sent successfully',
      messageId: message.id,
      delivered: false, // Will be updated when recipient comes online
      createdAt: message.createdAt
    });

  } catch (error) {
    console.error('Message send error:', error);
    res.status(500).json({ error: 'Failed to send message' });
  }
});

// Get offline messages for current user
router.get('/offline', validateMessageQuery, async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ 
        error: 'Validation failed', 
        details: errors.array() 
      });
    }

    const userId = req.user.id;
    const limit = parseInt(req.query.limit) || 50;
    const offset = parseInt(req.query.offset) || 0;

    const messages = await prisma.message.findMany({
      where: {
        recipientId: userId,
        delivered: false
      },
      include: {
        sender: {
          select: {
            id: true,
            username: true
          }
        }
      },
      orderBy: {
        createdAt: 'asc'
      },
      take: limit,
      skip: offset
    });

    // Mark messages as delivered
    if (messages.length > 0) {
      const messageIds = messages.map(msg => msg.id);
      await prisma.message.updateMany({
        where: {
          id: { in: messageIds }
        },
        data: {
          delivered: true
        }
      });
    }

    res.json({
      messages: messages.map(msg => ({
        id: msg.id,
        senderId: msg.senderId,
        senderUsername: msg.sender.username,
        recipientId: msg.recipientId,
        ciphertext: msg.ciphertext,
        messageType: msg.messageType,
        createdAt: msg.createdAt
      })),
      count: messages.length,
      hasMore: messages.length === limit
    });

  } catch (error) {
    console.error('Offline messages fetch error:', error);
    res.status(500).json({ error: 'Failed to fetch offline messages' });
  }
});

// Get conversation history with a specific user
router.get('/conversation/:userId', validateMessageQuery, async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ 
        error: 'Validation failed', 
        details: errors.array() 
      });
    }

    const { userId: otherUserId } = req.params;
    const currentUserId = req.user.id;
    const limit = parseInt(req.query.limit) || 50;
    const offset = parseInt(req.query.offset) || 0;

    // Verify other user exists
    const otherUser = await prisma.user.findUnique({
      where: { id: otherUserId },
      select: { id: true, username: true }
    });

    if (!otherUser) {
      return res.status(404).json({ error: 'User not found' });
    }

    const messages = await prisma.message.findMany({
      where: {
        OR: [
          { senderId: currentUserId, recipientId: otherUserId },
          { senderId: otherUserId, recipientId: currentUserId }
        ]
      },
      include: {
        sender: {
          select: {
            id: true,
            username: true
          }
        }
      },
      orderBy: {
        createdAt: 'desc'
      },
      take: limit,
      skip: offset
    });

    res.json({
      messages: messages.map(msg => ({
        id: msg.id,
        senderId: msg.senderId,
        senderUsername: msg.sender.username,
        recipientId: msg.recipientId,
        ciphertext: msg.ciphertext,
        messageType: msg.messageType,
        isFromMe: msg.senderId === currentUserId,
        createdAt: msg.createdAt
      })).reverse(), // Return in chronological order
      otherUser,
      count: messages.length,
      hasMore: messages.length === limit
    });

  } catch (error) {
    console.error('Conversation fetch error:', error);
    res.status(500).json({ error: 'Failed to fetch conversation' });
  }
});

// Acknowledge message receipt (for read receipts)
router.patch('/:messageId/acknowledge', async (req, res) => {
  try {
    const { messageId } = req.params;
    const userId = req.user.id;

    const message = await prisma.message.findUnique({
      where: { id: messageId }
    });

    if (!message) {
      return res.status(404).json({ error: 'Message not found' });
    }

    // Only recipient can acknowledge
    if (message.recipientId !== userId) {
      return res.status(403).json({ error: 'Not authorized to acknowledge this message' });
    }

    await prisma.message.update({
      where: { id: messageId },
      data: { acknowledged: true }
    });

    // Notify sender via Socket.IO
    const io = req.app.get('io');
    if (io) {
      io.to(`user_${message.senderId}`).emit('message_acknowledged', {
        messageId,
        acknowledgedBy: userId,
        acknowledgedAt: new Date()
      });
    }

    res.json({ message: 'Message acknowledged successfully' });

  } catch (error) {
    console.error('Message acknowledge error:', error);
    res.status(500).json({ error: 'Failed to acknowledge message' });
  }
});

// Get message statistics for current user
router.get('/stats', async (req, res) => {
  try {
    const userId = req.user.id;

    const [sentCount, receivedCount, undeliveredCount] = await Promise.all([
      prisma.message.count({ where: { senderId: userId } }),
      prisma.message.count({ where: { recipientId: userId } }),
      prisma.message.count({ 
        where: { 
          recipientId: userId, 
          delivered: false 
        } 
      })
    ]);

    res.json({
      sent: sentCount,
      received: receivedCount,
      undelivered: undeliveredCount
    });

  } catch (error) {
    console.error('Message stats error:', error);
    res.status(500).json({ error: 'Failed to get message statistics' });
  }
});

module.exports = router;
