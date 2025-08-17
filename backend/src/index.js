const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const { createServer } = require('http');
const { Server } = require('socket.io');
require('dotenv').config();

const authRoutes = require('./routes/auth');
const prekeyRoutes = require('./routes/prekeys');
const messageRoutes = require('./routes/messages');
const userRoutes = require('./routes/users');

const authMiddleware = require('./middleware/auth');
const errorHandler = require('./middleware/errorHandler');
const { rateLimiter } = require('./middleware/rateLimiter');

const SocketService = require('./services/socketService');

const app = express();
const server = createServer(app);
const io = new Server(server, {
  cors: {
    origin: process.env.CORS_ORIGIN || "http://localhost:3000",
    methods: ["GET", "POST"]
  }
});

const PORT = process.env.PORT || 3000;

// Middleware
app.use(helmet());
app.use(cors({
  origin: process.env.CORS_ORIGIN || "http://localhost:3000"
}));
app.use(morgan('combined'));
app.use(express.json({ limit: '10mb' })); // Larger limit for encrypted messages
app.use(rateLimiter);

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'OK', timestamp: new Date().toISOString() });
});

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/prekeys', authMiddleware, prekeyRoutes);
app.use('/api/messages', authMiddleware, messageRoutes);
app.use('/api/users', authMiddleware, userRoutes);

// Initialize Socket.IO service
const socketService = new SocketService(io);
socketService.initialize();

// Make io available to routes
app.set('io', io);

// Error handling
app.use(errorHandler);

// Start server
server.listen(PORT, () => {
  console.log(`🚀 Encrypted Chat Backend running on port ${PORT}`);
  console.log(`📡 Socket.IO enabled for real-time messaging`);
  console.log(`🔒 Security headers enabled with Helmet`);
  console.log(`📊 Request logging enabled with Morgan`);
});

module.exports = app;
