# Backend Project Structure

```
backend/
├── src/
│   ├── index.js                 # Main server entry point
│   ├── middleware/
│   │   ├── auth.js             # JWT authentication middleware
│   │   ├── errorHandler.js     # Global error handling
│   │   └── rateLimiter.js      # Rate limiting middleware
│   ├── routes/
│   │   ├── auth.js             # Authentication endpoints
│   │   ├── prekeys.js          # Prekey management (E2E crypto)
│   │   ├── messages.js         # Message relay endpoints
│   │   └── users.js            # User management endpoints
│   ├── services/
│   │   └── socketService.js    # WebSocket/Socket.IO service
│   └── utils/                  # Utility functions (empty for now)
├── prisma/
│   └── schema.prisma           # Database schema definition
├── node_modules/               # Dependencies
├── package.json                # Project configuration
├── package-lock.json           # Dependency lock file
├── README.md                   # Project documentation
├── PROJECT_STRUCTURE.md        # This file
├── env.template                # Environment variables template
└── test-endpoints.js           # Simple API testing script
```

## 🔧 Key Components

### Core Server (`src/index.js`)
- Express.js application setup
- Middleware configuration (CORS, Helmet, Morgan)
- Route registration
- Socket.IO integration
- Error handling

### Authentication (`src/middleware/auth.js`, `src/routes/auth.js`)
- JWT token validation
- User registration/login
- Password hashing with bcrypt
- Token verification endpoints

### Prekey Management (`src/routes/prekeys.js`)
- Upload signed prekeys and one-time prekeys
- Fetch prekey bundles for X3DH handshake
- Automatic one-time prekey consumption
- Prekey count tracking

### Message Relay (`src/routes/messages.js`)
- Send encrypted messages
- Fetch offline messages
- Conversation history
- Message acknowledgment system

### User Management (`src/routes/users.js`)
- User search functionality
- Profile management
- Recent conversations
- User statistics

### Real-time Communication (`src/services/socketService.js`)
- Socket.IO authentication
- Typing indicators
- Online status tracking
- Message delivery confirmations
- Real-time message broadcasting

### Database Schema (`prisma/schema.prisma`)
- **Users**: Authentication and identity keys
- **Prekeys**: Signed prekeys for each user
- **OneTimePrekeys**: Forward secrecy keys
- **Messages**: Encrypted message storage

## 🔐 Security Features

1. **Authentication**:
   - JWT tokens with expiration
   - Bcrypt password hashing (12 rounds)
   - Rate limiting on auth endpoints

2. **Input Validation**:
   - Express-validator for all inputs
   - Base64 validation for cryptographic data
   - SQL injection prevention via Prisma

3. **Rate Limiting**:
   - General API rate limiting
   - Stricter limits for authentication
   - IP-based throttling

4. **Error Handling**:
   - Secure error messages
   - No sensitive data in responses
   - Comprehensive logging

## 🔌 WebSocket Events

### Authentication
- JWT token required for socket connections
- User rooms for private messaging

### Real-time Features
- Typing indicators
- Online/offline status
- Message delivery confirmations
- Instant message notifications

## 📊 Database Design

### Key Relationships
- Users ←→ Prekeys (1:1)
- Users ←→ OneTimePrekeys (1:N)
- Users ←→ Messages (sender/recipient)

### Indexes
- Message recipient + delivery status
- Message sender + creation time
- One-time prekey user + key ID

## 🚀 Getting Started

1. **Install dependencies**: `npm install`
2. **Setup database**: Copy `env.template` to `.env`
3. **Run migrations**: `npx prisma db push`
4. **Generate client**: `npx prisma generate`
5. **Start server**: `npm run dev`
6. **Test endpoints**: `node test-endpoints.js`

## 🧪 Testing

The `test-endpoints.js` script provides basic functionality testing:
- Health check
- User registration/login
- Prekey upload/fetch
- Message sending
- Token verification

Run after starting the server to verify everything works.

## 📝 Next Steps

1. **Flutter Frontend**: Implement client-side encryption
2. **Signal Protocol**: Add Double Ratchet implementation
3. **File Uploads**: Support for encrypted file sharing
4. **Group Chat**: Multi-party conversation support
5. **Backup/Restore**: Key backup mechanisms
6. **Admin Panel**: User management interface
