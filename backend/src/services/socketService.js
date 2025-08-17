const jwt = require('jsonwebtoken');
const { PrismaClient } = require('@prisma/client');

class SocketService {
  constructor(io) {
    this.io = io;
    this.prisma = new PrismaClient();
    this.connectedUsers = new Map(); // userId -> socketId mapping
  }

  initialize() {
    this.io.use(this.authenticateSocket.bind(this));
    this.io.on('connection', this.handleConnection.bind(this));
    
    console.log('📡 Socket.IO service initialized');
  }

  // Authenticate socket connections
  async authenticateSocket(socket, next) {
    try {
      const token = socket.handshake.auth.token || socket.handshake.headers.authorization?.replace('Bearer ', '');
      
      if (!token) {
        return next(new Error('Authentication error: No token provided'));
      }

      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      
      // Verify user exists
      const user = await this.prisma.user.findUnique({
        where: { id: decoded.userId },
        select: { id: true, username: true }
      });

      if (!user) {
        return next(new Error('Authentication error: User not found'));
      }

      socket.userId = user.id;
      socket.username = user.username;
      next();

    } catch (error) {
      console.error('Socket authentication error:', error.message);
      next(new Error('Authentication error: Invalid token'));
    }
  }

  // Handle new socket connections
  handleConnection(socket) {
    const userId = socket.userId;
    const username = socket.username;

    console.log(`🔌 User connected: ${username} (${userId})`);

    // Store connection
    this.connectedUsers.set(userId, socket.id);

    // Join user to their personal room
    socket.join(`user_${userId}`);

    // Notify user they're connected
    socket.emit('connected', {
      message: 'Connected to encrypted chat server',
      userId,
      username
    });

    // Handle typing indicators
    socket.on('typing_start', (data) => {
      this.handleTypingStart(socket, data);
    });

    socket.on('typing_stop', (data) => {
      this.handleTypingStop(socket, data);
    });

    // Handle user status updates
    socket.on('status_update', (data) => {
      this.handleStatusUpdate(socket, data);
    });

    // Handle message delivery confirmation
    socket.on('message_delivered', (data) => {
      this.handleMessageDelivered(socket, data);
    });

    // Handle disconnection
    socket.on('disconnect', () => {
      this.handleDisconnection(socket);
    });

    // Handle errors
    socket.on('error', (error) => {
      console.error(`Socket error for user ${username}:`, error);
    });
  }

  // Handle typing start indicator
  handleTypingStart(socket, data) {
    try {
      const { recipientId } = data;
      
      if (!recipientId) {
        return socket.emit('error', { message: 'Recipient ID required for typing indicator' });
      }

      // Send typing indicator to recipient
      socket.to(`user_${recipientId}`).emit('user_typing', {
        userId: socket.userId,
        username: socket.username,
        typing: true
      });

    } catch (error) {
      console.error('Typing start error:', error);
      socket.emit('error', { message: 'Failed to send typing indicator' });
    }
  }

  // Handle typing stop indicator
  handleTypingStop(socket, data) {
    try {
      const { recipientId } = data;
      
      if (!recipientId) {
        return socket.emit('error', { message: 'Recipient ID required for typing indicator' });
      }

      // Send typing stop indicator to recipient
      socket.to(`user_${recipientId}`).emit('user_typing', {
        userId: socket.userId,
        username: socket.username,
        typing: false
      });

    } catch (error) {
      console.error('Typing stop error:', error);
      socket.emit('error', { message: 'Failed to send typing indicator' });
    }
  }

  // Handle user status updates (online/away/busy)
  handleStatusUpdate(socket, data) {
    try {
      const { status } = data;
      
      if (!['online', 'away', 'busy'].includes(status)) {
        return socket.emit('error', { message: 'Invalid status' });
      }

      // Broadcast status to all connected users (or implement friend lists)
      socket.broadcast.emit('user_status_changed', {
        userId: socket.userId,
        username: socket.username,
        status
      });

    } catch (error) {
      console.error('Status update error:', error);
      socket.emit('error', { message: 'Failed to update status' });
    }
  }

  // Handle message delivery confirmation
  async handleMessageDelivered(socket, data) {
    try {
      const { messageId } = data;
      
      if (!messageId) {
        return socket.emit('error', { message: 'Message ID required' });
      }

      // Update message as delivered in database
      const message = await this.prisma.message.findUnique({
        where: { id: messageId },
        include: { sender: true }
      });

      if (!message) {
        return socket.emit('error', { message: 'Message not found' });
      }

      // Only recipient can mark as delivered
      if (message.recipientId !== socket.userId) {
        return socket.emit('error', { message: 'Not authorized' });
      }

      await this.prisma.message.update({
        where: { id: messageId },
        data: { delivered: true }
      });

      // Notify sender
      socket.to(`user_${message.senderId}`).emit('message_delivered', {
        messageId,
        deliveredAt: new Date(),
        deliveredBy: socket.userId
      });

    } catch (error) {
      console.error('Message delivered error:', error);
      socket.emit('error', { message: 'Failed to mark message as delivered' });
    }
  }

  // Handle user disconnection
  handleDisconnection(socket) {
    const userId = socket.userId;
    const username = socket.username;

    console.log(`🔌 User disconnected: ${username} (${userId})`);

    // Remove from connected users
    this.connectedUsers.delete(userId);

    // Broadcast user offline status
    socket.broadcast.emit('user_status_changed', {
      userId,
      username,
      status: 'offline'
    });
  }

  // Check if user is online
  isUserOnline(userId) {
    return this.connectedUsers.has(userId);
  }

  // Get connected user count
  getConnectedUserCount() {
    return this.connectedUsers.size;
  }

  // Send message to specific user
  sendToUser(userId, event, data) {
    this.io.to(`user_${userId}`).emit(event, data);
  }

  // Broadcast to all connected users
  broadcast(event, data) {
    this.io.emit(event, data);
  }
}

module.exports = SocketService;
