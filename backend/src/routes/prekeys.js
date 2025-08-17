const express = require('express');
const { PrismaClient } = require('@prisma/client');
const { body, validationResult } = require('express-validator');

const router = express.Router();
const prisma = new PrismaClient();

// Validation middleware
const validatePrekeyUpload = [
  body('signedPrekey')
    .isBase64()
    .withMessage('Signed prekey must be valid base64'),
  body('prekeySignature')
    .isBase64()
    .withMessage('Prekey signature must be valid base64'),
  body('keyId')
    .isInt({ min: 0 })
    .withMessage('Key ID must be a non-negative integer'),
  body('oneTimePrekeys')
    .isArray({ min: 1, max: 100 })
    .withMessage('Must provide 1-100 one-time prekeys'),
  body('oneTimePrekeys.*')
    .isBase64()
    .withMessage('All one-time prekeys must be valid base64')
];

// Upload prekeys for a user
router.post('/upload', validatePrekeyUpload, async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ 
        error: 'Validation failed', 
        details: errors.array() 
      });
    }

    const { signedPrekey, prekeySignature, keyId, oneTimePrekeys } = req.body;
    const userId = req.user.id;

    await prisma.$transaction(async (tx) => {
      // Upsert signed prekey (replace existing one)
      await tx.prekey.upsert({
        where: { userId },
        update: {
          signedPrekey,
          prekeySignature,
          keyId
        },
        create: {
          userId,
          signedPrekey,
          prekeySignature,
          keyId
        }
      });

      // Delete existing one-time prekeys for this user
      await tx.oneTimePrekey.deleteMany({
        where: { userId }
      });

      // Insert new one-time prekeys
      const prekeyData = oneTimePrekeys.map((pubkey, index) => ({
        userId,
        pubkey,
        keyId: index
      }));

      await tx.oneTimePrekey.createMany({
        data: prekeyData
      });
    });

    res.json({
      message: 'Prekeys uploaded successfully',
      signedPrekeyId: keyId,
      oneTimePrekeyCount: oneTimePrekeys.length
    });

  } catch (error) {
    console.error('Prekey upload error:', error);
    res.status(500).json({ error: 'Failed to upload prekeys' });
  }
});

// Get prekey bundle for a user (for initiating conversations)
router.get('/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    // Check if target user exists
    const targetUser = await prisma.user.findUnique({
      where: { id: userId },
      select: { 
        id: true, 
        username: true, 
        identityPubkey: true 
      }
    });

    if (!targetUser) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Get signed prekey
    const signedPrekey = await prisma.prekey.findUnique({
      where: { userId }
    });

    if (!signedPrekey) {
      return res.status(404).json({ 
        error: 'No prekeys available for this user' 
      });
    }

    // Get and consume one one-time prekey
    let oneTimePrekey = null;
    const availableOTP = await prisma.oneTimePrekey.findFirst({
      where: { userId },
      orderBy: { createdAt: 'asc' }
    });

    if (availableOTP) {
      // Remove the one-time prekey after fetching it
      await prisma.oneTimePrekey.delete({
        where: { id: availableOTP.id }
      });
      oneTimePrekey = {
        keyId: availableOTP.keyId,
        pubkey: availableOTP.pubkey
      };
    }

    res.json({
      userId: targetUser.id,
      username: targetUser.username,
      identityPubkey: targetUser.identityPubkey,
      signedPrekey: {
        keyId: signedPrekey.keyId,
        pubkey: signedPrekey.signedPrekey,
        signature: signedPrekey.prekeySignature
      },
      oneTimePrekey
    });

  } catch (error) {
    console.error('Prekey fetch error:', error);
    res.status(500).json({ error: 'Failed to fetch prekey bundle' });
  }
});

// Get prekey count for current user (to know when to upload more)
router.get('/count/mine', async (req, res) => {
  try {
    const userId = req.user.id;

    const [signedPrekeyCount, oneTimePrekeyCount] = await Promise.all([
      prisma.prekey.count({ where: { userId } }),
      prisma.oneTimePrekey.count({ where: { userId } })
    ]);

    res.json({
      signedPrekeys: signedPrekeyCount,
      oneTimePrekeys: oneTimePrekeyCount
    });

  } catch (error) {
    console.error('Prekey count error:', error);
    res.status(500).json({ error: 'Failed to get prekey count' });
  }
});

// Bulk upload additional one-time prekeys
router.post('/otp/bulk', async (req, res) => {
  try {
    const { oneTimePrekeys } = req.body;
    const userId = req.user.id;

    if (!Array.isArray(oneTimePrekeys) || oneTimePrekeys.length === 0 || oneTimePrekeys.length > 100) {
      return res.status(400).json({ 
        error: 'Must provide 1-100 one-time prekeys' 
      });
    }

    // Validate all prekeys are base64
    for (const prekey of oneTimePrekeys) {
      if (!Buffer.from(prekey, 'base64').toString('base64') === prekey) {
        return res.status(400).json({ 
          error: 'All one-time prekeys must be valid base64' 
        });
      }
    }

    // Get the current highest keyId for this user
    const lastKey = await prisma.oneTimePrekey.findFirst({
      where: { userId },
      orderBy: { keyId: 'desc' }
    });

    const startKeyId = lastKey ? lastKey.keyId + 1 : 0;

    // Insert new one-time prekeys
    const prekeyData = oneTimePrekeys.map((pubkey, index) => ({
      userId,
      pubkey,
      keyId: startKeyId + index
    }));

    await prisma.oneTimePrekey.createMany({
      data: prekeyData
    });

    res.json({
      message: 'One-time prekeys uploaded successfully',
      count: oneTimePrekeys.length,
      startKeyId
    });

  } catch (error) {
    console.error('Bulk OTP upload error:', error);
    res.status(500).json({ error: 'Failed to upload one-time prekeys' });
  }
});

module.exports = router;
