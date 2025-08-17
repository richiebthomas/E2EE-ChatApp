const express = require('express');
const { PrismaClient } = require('@prisma/client');
const { query, body, validationResult } = require('express-validator');

const router = express.Router();
const prisma = new PrismaClient();

// Validation middleware
const validateUserSearch = [
  query('q')
    .optional()
    .isLength({ min: 1, max: 50 })
    .withMessage('Search query must be between 1 and 50 characters'),
  query('limit')
    .optional()
    .isInt({ min: 1, max: 50 })
    .withMessage('Limit must be between 1 and 50')
];

// Get current user profile
router.get('/me', async (req, res) => {
  try {
    const userId = req.user.id;

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        username: true,
        email: true,
        identityPubkey: true,
        createdAt: true,
        updatedAt: true
      }
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Get additional stats
    const [sentCount, receivedCount, prekeyCount] = await Promise.all([
      prisma.message.count({ where: { senderId: userId } }),
      prisma.message.count({ where: { recipientId: userId } }),
      prisma.oneTimePrekey.count({ where: { userId } })
    ]);

    res.json({
      user,
      stats: {
        messagesSent: sentCount,
        messagesReceived: receivedCount,
        oneTimePrekeyCount: prekeyCount
      }
    });

  } catch (error) {
    console.error('Get user profile error:', error);
    res.status(500).json({ error: 'Failed to get user profile' });
  }
});

// Rotate identity public key (client has lost keys and needs to re-enroll)
router.post('/identity/rotate',
  body('identityPubkey').isBase64().withMessage('Identity public key must be valid base64'),
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({ error: 'Validation failed', details: errors.array() });
      }

      const userId = req.user.id;
      const { identityPubkey } = req.body;

      // Update identity key and clear existing prekeys so client can upload fresh ones
      await prisma.$transaction(async (tx) => {
        await tx.user.update({
          where: { id: userId },
          data: { identityPubkey }
        });

        await tx.prekey.deleteMany({ where: { userId } });
        await tx.oneTimePrekey.deleteMany({ where: { userId } });
      });

      res.json({ message: 'Identity key rotated. Please upload new prekeys.' });
    } catch (error) {
      console.error('Identity rotate error:', error);
      res.status(500).json({ error: 'Failed to rotate identity key' });
    }
  }
);

// Search users (for finding people to chat with)
router.get('/search', validateUserSearch, async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ 
        error: 'Validation failed', 
        details: errors.array() 
      });
    }

    const { q: searchQuery, limit = 20 } = req.query;
    const currentUserId = req.user.id;

    let users;
    
    if (searchQuery) {
      // Search by username or email
      users = await prisma.user.findMany({
        where: {
          AND: [
            { id: { not: currentUserId } }, // Exclude current user
            {
              OR: [
                { username: { contains: searchQuery, mode: 'insensitive' } },
                { email: { contains: searchQuery, mode: 'insensitive' } }
              ]
            }
          ]
        },
        select: {
          id: true,
          username: true,
          email: true,
          createdAt: true
        },
        take: parseInt(limit),
        orderBy: {
          username: 'asc'
        }
      });
    } else {
      // Return recent users (if no search query)
      users = await prisma.user.findMany({
        where: {
          id: { not: currentUserId }
        },
        select: {
          id: true,
          username: true,
          email: true,
          createdAt: true
        },
        take: parseInt(limit),
        orderBy: {
          createdAt: 'desc'
        }
      });
    }

    res.json({
      users,
      count: users.length,
      searchQuery: searchQuery || null
    });

  } catch (error) {
    console.error('User search error:', error);
    res.status(500).json({ error: 'Failed to search users' });
  }
});

// Get user by ID (public profile)
router.get('/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        username: true,
        createdAt: true
        // Note: Not including email or identity key for privacy
      }
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json({ user });

  } catch (error) {
    console.error('Get user by ID error:', error);
    res.status(500).json({ error: 'Failed to get user' });
  }
});

// Get recent conversations for current user
router.get('/conversations/recent', async (req, res) => {
  try {
    const userId = req.user.id;
    const limit = parseInt(req.query.limit) || 20;

    // Get recent conversations by finding the latest message with each user
    // Use a simpler approach with a window function
    const recentMessages = await prisma.$queryRaw`
      WITH ranked_messages AS (
        SELECT 
          CASE 
            WHEN "senderId" = ${userId} THEN "recipientId" 
            ELSE "senderId" 
          END as other_user_id,
          id,
          "senderId",
          "recipientId",
          ciphertext,
          "messageType",
          "createdAt",
          delivered,
          acknowledged,
          ROW_NUMBER() OVER (
            PARTITION BY (
              CASE 
                WHEN "senderId" = ${userId} THEN "recipientId" 
                ELSE "senderId" 
              END
            ) 
            ORDER BY "createdAt" DESC
          ) as rn
        FROM messages 
        WHERE "senderId" = ${userId} OR "recipientId" = ${userId}
      )
      SELECT 
        other_user_id,
        id,
        "senderId",
        "recipientId",
        ciphertext,
        "messageType",
        "createdAt",
        delivered,
        acknowledged
      FROM ranked_messages 
      WHERE rn = 1
      ORDER BY "createdAt" DESC
      LIMIT ${limit}
    `;

    // Get user details for each conversation
    const otherUserIds = recentMessages.map(msg => msg.other_user_id);
    const otherUsers = await prisma.user.findMany({
      where: {
        id: { in: otherUserIds }
      },
      select: {
        id: true,
        username: true
      }
    });

    // Combine the data
    const conversations = recentMessages.map(msg => {
      const otherUser = otherUsers.find(user => user.id === msg.other_user_id);
      return {
        otherUser,
        lastMessage: {
          id: msg.id || 'unknown',
          senderId: msg.senderId,
          recipientId: msg.recipientId,
          ciphertext: msg.ciphertext,
          messageType: msg.messageType,
          createdAt: msg.createdAt,
          delivered: msg.delivered,
          acknowledged: msg.acknowledged,
          isFromMe: msg.senderId === userId
        }
      };
    });

    res.json({
      conversations,
      count: conversations.length
    });

  } catch (error) {
    console.error('Recent conversations error:', error);
    res.status(500).json({ error: 'Failed to get recent conversations' });
  }
});

module.exports = router;
