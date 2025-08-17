# Encrypted Chat Backend

A secure, end-to-end encrypted chat application backend built with Node.js, Express, and PostgreSQL. This backend serves as a "dumb relay" - it stores only encrypted messages and public keys, never having access to private keys or plaintext messages.

## 🔒 Security Architecture

- **End-to-End Encryption**: All encryption/decryption happens client-side
- **Signal Protocol**: Uses X3DH key agreement and Double Ratchet
- **Public Key Storage**: Only stores public identity keys and prekeys
- **Forward Secrecy**: One-time prekeys are consumed after use
- **Zero Knowledge**: Server never sees plaintext messages

## 🚀 Features

- **User Authentication**: JWT-based auth with bcrypt password hashing
- **Prekey Management**: Upload/fetch prekey bundles for X3DH handshake
- **Message Relay**: Store and forward encrypted messages
- **Real-time Messaging**: WebSocket support with Socket.IO
- **Offline Messages**: Messages stored until recipient comes online
- **Rate Limiting**: Protection against spam and abuse
- **Input Validation**: Comprehensive validation with express-validator

## 📋 Prerequisites

- Node.js (v16 or higher)
- PostgreSQL (v12 or higher)
- npm or yarn

## 🛠 Installation

1. **Clone and setup**:
   ```bash
   cd backend
   npm install
   ```

2. **Database setup**:
   ```bash
   # Create PostgreSQL database
   createdb encrypted_chat
   
   # Copy environment file
   cp .env.example .env
   
   # Edit .env with your database credentials
   nano .env
   ```

3. **Environment variables** (`.env`):
   ```env
   DATABASE_URL="postgresql://username:password@localhost:5432/encrypted_chat?schema=public"
   JWT_SECRET="your-super-secret-jwt-key-change-this-in-production"
   PORT=3000
   NODE_ENV=development
   CORS_ORIGIN="http://localhost:3000"
   ```

4. **Database migration**:
   ```bash
   npx prisma db push
   npx prisma generate
   ```

5. **Start server**:
   ```bash
   # Development mode (with auto-restart)
   npm run dev
   
   # Production mode
   npm start
   ```

## 📡 API Endpoints

### Authentication
- `POST /api/auth/register` - Register new user
- `POST /api/auth/login` - Login user
- `GET /api/auth/verify` - Verify JWT token

### Prekey Management
- `POST /api/prekeys/upload` - Upload signed prekey + one-time prekeys
- `GET /api/prekeys/:userId` - Fetch prekey bundle for user
- `GET /api/prekeys/count/mine` - Get prekey count for current user
- `POST /api/prekeys/otp/bulk` - Upload additional one-time prekeys

### Messages
- `POST /api/messages/send` - Send encrypted message
- `GET /api/messages/offline` - Get undelivered messages
- `GET /api/messages/conversation/:userId` - Get conversation history
- `PATCH /api/messages/:messageId/acknowledge` - Mark message as read

### Users
- `GET /api/users/me` - Get current user profile
- `GET /api/users/search` - Search users
- `GET /api/users/:userId` - Get user by ID
- `GET /api/users/conversations/recent` - Get recent conversations

## 🔌 WebSocket Events

### Client → Server
- `typing_start` - Start typing indicator
- `typing_stop` - Stop typing indicator
- `message_delivered` - Confirm message delivery
- `status_update` - Update user status

### Server → Client
- `connected` - Connection confirmation
- `new_message` - New encrypted message received
- `user_typing` - User typing indicator
- `message_delivered` - Message delivery confirmation
- `user_status_changed` - User status update

## 🗄 Database Schema

### Users
- `id` (UUID) - Primary key
- `username` (String) - Unique username
- `email` (String) - Unique email
- `passwordHash` (String) - Bcrypt hashed password
- `identityPubkey` (String) - User's identity public key

### Prekeys
- `userId` (UUID) - Foreign key to users
- `signedPrekey` (String) - Signed prekey (base64)
- `prekeySignature` (String) - Signature of signed prekey
- `keyId` (Int) - Sequential key ID

### OneTimePrekeys
- `userId` (UUID) - Foreign key to users
- `pubkey` (String) - One-time prekey (base64)
- `keyId` (Int) - Sequential key ID

### Messages
- `senderId` (UUID) - Foreign key to users
- `recipientId` (UUID) - Foreign key to users
- `ciphertext` (String) - Encrypted message (base64)
- `messageType` - REGULAR | KEY_EXCHANGE | PREKEY_REQUEST
- `delivered` (Boolean) - Delivery status
- `acknowledged` (Boolean) - Read receipt

## 🛡 Security Considerations

### In Production:
1. **Use HTTPS**: All API calls must be over HTTPS
2. **Strong JWT Secret**: Use a cryptographically secure random string
3. **Database Security**: Use connection pooling and prepared statements
4. **Rate Limiting**: Adjust limits based on your traffic patterns
5. **Input Validation**: All user inputs are validated and sanitized
6. **CORS**: Configure CORS for your frontend domain only

### Key Management:
- Private keys are NEVER stored on the server
- One-time prekeys are deleted after use (forward secrecy)
- Identity keys should be backed up by clients securely

## 🔧 Development

```bash
# Watch mode with nodemon
npm run dev

# Database operations
npm run db:generate  # Generate Prisma client
npm run db:push      # Push schema changes
npm run db:migrate   # Run migrations
npm run db:studio    # Open Prisma Studio

# Linting (if eslint configured)
npm run lint
```

## 📊 Monitoring

- Health check: `GET /health`
- Connected users: Check server logs
- Database metrics: Use Prisma metrics or pg_stat_* views

## 🤝 Integration with Flutter

This backend is designed to work with a Flutter frontend using:
- `http` package for REST API calls
- `socket_io_client` for real-time messaging
- `flutter_secure_storage` for private key storage
- Signal Protocol implementation for E2E encryption

## 📄 License

MIT License - See LICENSE file for details
