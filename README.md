# ChatApp - End-to-End Encrypted Messaging Platform

A modern, secure messaging application implementing state-of-the-art cryptographic protocols including Diffie-Hellman key exchange, RSA-style public key cryptography, and the Signal Protocol for bulletproof end-to-end encryption. Built with Flutter for cross-platform mobile support and Node.js for a robust backend infrastructure.

## 🔐 Security Features

- **Signal Protocol Implementation**: Industry-standard end-to-end encryption used by WhatsApp, Signal, and other secure messengers
- **X3DH Key Agreement**: Advanced key exchange protocol combining Diffie-Hellman with elliptic curve cryptography
- **Double Ratchet Algorithm**: Provides forward secrecy and post-compromise security
- **Ed25519 & X25519**: Modern elliptic curve cryptography for digital signatures and key exchange
- **AES-GCM Encryption**: Authenticated encryption ensuring both confidentiality and integrity
- **Perfect Forward Secrecy**: Each message uses a unique encryption key that's automatically deleted

## 🏗️ Architecture

### Frontend (Flutter/Dart)
```
lib/
├── models/                 # Data models (User, Message, etc.)
├── screens/               # UI screens and navigation
├── services/              # Core business logic
│   ├── signal_protocol/   # End-to-end encryption implementation
│   ├── api_service.dart   # HTTP API communication
│   ├── crypto_service.dart # Cryptographic operations
│   ├── message_service.dart # Message handling and encryption
│   └── socket_service.dart # Real-time communication
├── utils/                 # Constants and utilities
└── widgets/              # Reusable UI components
```

### Backend (Node.js/Express)
```
src/
├── routes/               # API endpoints
│   ├── auth.js          # Authentication and user management
│   ├── messages.js      # Message storage and retrieval
│   ├── prekeys.js       # Cryptographic key management
│   └── users.js         # User profiles and search
├── services/            # Business logic
│   ├── authService.js   # JWT authentication
│   └── socketService.js # Real-time messaging via Socket.IO
├── middleware/          # Express middleware
└── utils/              # Database and utility functions
```

## 🛠️ Technology Stack

### Frontend
- **Flutter 3.x**: Cross-platform mobile development framework
- **Dart**: Programming language optimized for mobile and web
- **cryptography**: Dart package for Signal Protocol implementation
- **socket_io_client**: Real-time bidirectional communication
- **flutter_secure_storage**: Secure local storage for cryptographic keys
- **provider**: State management for reactive UI updates

### Backend
- **Node.js 18+**: JavaScript runtime for server-side development
- **Express.js**: Fast, minimalist web framework
- **Socket.IO**: Real-time WebSocket communication
- **PostgreSQL**: Robust relational database for message storage
- **Prisma**: Modern ORM for type-safe database operations
- **JWT**: JSON Web Tokens for stateless authentication
- **bcrypt**: Password hashing with salt for security

### Deployment & DevOps
- **Vercel**: Serverless deployment platform for the backend
- **Android Studio**: IDE for Android app development and testing
- **Docker**: Containerization for consistent development environments

## 🔑 Cryptographic Implementation

### Key Exchange Protocol (X3DH)
1. **Identity Keys**: Long-term Ed25519 keypairs for user identification
2. **Signed Prekeys**: Medium-term X25519 keypairs, signed with identity keys
3. **One-Time Prekeys**: Single-use X25519 keypairs for enhanced security
4. **Ephemeral Keys**: Temporary keys generated for each conversation

### Message Encryption Flow
1. **Session Establishment**: X3DH key agreement creates shared secret
2. **Root Key Derivation**: HKDF generates master encryption keys
3. **Chain Key Evolution**: Double Ratchet algorithm advances encryption state
4. **Message Encryption**: AES-GCM with unique keys and nonces
5. **Forward Secrecy**: Old keys are deleted, ensuring past messages remain secure

### Security Properties
- **End-to-End Encryption**: Only sender and recipient can read messages
- **Forward Secrecy**: Compromised keys don't affect past messages
- **Post-Compromise Security**: Future messages remain secure after key compromise
- **Replay Protection**: Each message has a unique authentication tag
- **Identity Verification**: Digital signatures prevent impersonation attacks

## 🚀 Getting Started

### Prerequisites
- **Flutter SDK 3.0+**
- **Node.js 18+**
- **PostgreSQL 14+**
- **Android Studio** (for Android development)

### Backend Setup
```bash
cd backend
npm install
cp .env.example .env
# Configure your database URL and JWT secret in .env
npx prisma migrate dev
npm run dev
```

### Frontend Setup
```bash
cd frontend
flutter pub get
flutter run
```

### Environment Configuration
Create `.env` in the backend directory:
```env
DATABASE_URL="postgresql://user:password@localhost:5432/chatapp"
JWT_SECRET="your-super-secret-jwt-key"
CORS_ORIGIN="http://localhost:3000"
```

## 📱 Features

### Core Messaging
- **Real-time messaging** with Socket.IO
- **Message delivery confirmations** and read receipts
- **Typing indicators** for enhanced user experience
- **Message history** with reliable synchronization
- **Cross-platform support** (Android, iOS)

### Security Features
- **Automatic key generation** and rotation
- **Session management** with persistent storage
- **Key verification** to prevent man-in-the-middle attacks
- **Secure key backup** and recovery mechanisms
- **Perfect forward secrecy** for all conversations

### User Experience
- **Modern Material Design** interface
- **Dark/Light theme** support
- **Offline message queuing** and synchronization
- **Push notifications** for new messages
- **User search** and discovery

## 🔧 Development

### Running Tests
```bash
# Backend tests
cd backend && npm test

# Frontend tests
cd frontend && flutter test
```

### Building for Production
```bash
# Android APK
cd frontend && flutter build apk --release

# iOS (requires macOS and Xcode)
cd frontend && flutter build ios --release
```

### Database Migrations
```bash
cd backend
npx prisma migrate dev --name add_new_feature
npx prisma generate
```

## 📡 API Endpoints

### Authentication
- `POST /api/auth/register` - User registration
- `POST /api/auth/login` - User authentication
- `POST /api/auth/refresh` - Token refresh

### Messaging
- `GET /api/messages/:userId` - Fetch conversation history
- `POST /api/messages` - Send encrypted message
- `PUT /api/messages/:id/acknowledge` - Mark message as read

### Key Management
- `POST /api/prekeys` - Upload prekey bundle
- `GET /api/prekeys/:userId` - Fetch user's prekeys
- `POST /api/users/identity/rotate` - Rotate identity keys

## 🛡️ Security Considerations

### Key Storage
- **Client-side**: Keys stored in secure hardware-backed keystores
- **Server-side**: Only public keys and encrypted prekeys stored
- **In-transit**: All API calls use HTTPS with certificate pinning

### Threat Model
- **Passive Network Adversary**: Cannot decrypt intercepted messages
- **Active Network Adversary**: Cannot inject or modify messages undetected
- **Server Compromise**: Cannot access message plaintext or private keys
- **Device Compromise**: Forward secrecy limits exposure window


## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 🔗 References

- [Signal Protocol Documentation](https://signal.org/docs/)
- [X3DH Key Agreement Protocol](https://signal.org/docs/specifications/x3dh/)
- [Double Ratchet Algorithm](https://signal.org/docs/specifications/doubleratchet/)
- [Flutter Cryptography Package](https://pub.dev/packages/cryptography)


