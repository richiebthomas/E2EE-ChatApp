# Flutter Frontend Structure

```
frontend/
├── lib/
│   ├── main.dart                    # App entry point
│   ├── models/
│   │   ├── user.dart               # User model
│   │   ├── message.dart            # Message model with encryption support
│   │   ├── prekey_bundle.dart      # Prekey bundle for X3DH
│   │   └── conversation.dart       # Conversation model
│   ├── services/
│   │   ├── api_service.dart        # HTTP API client
│   │   ├── secure_storage_service.dart # Private key storage
│   │   ├── crypto_service.dart     # Cryptographic functions
│   │   ├── socket_service.dart     # WebSocket/real-time (TODO)
│   │   └── auth_service.dart       # Authentication management (TODO)
│   ├── screens/
│   │   ├── auth/
│   │   │   ├── login_screen.dart   # Login UI (TODO)
│   │   │   └── register_screen.dart # Registration UI (TODO)
│   │   ├── chat/
│   │   │   ├── chat_list_screen.dart # Conversation list (TODO)
│   │   │   ├── chat_screen.dart    # Individual chat (TODO)
│   │   │   └── new_chat_screen.dart # Start new chat (TODO)
│   │   └── settings/
│   │       └── settings_screen.dart # App settings (TODO)
│   ├── widgets/
│   │   ├── message_bubble.dart     # Message UI component (TODO)
│   │   ├── encryption_indicator.dart # Security status (TODO)
│   │   └── loading_widget.dart     # Loading states (TODO)
│   └── utils/
│       ├── constants.dart          # App constants (TODO)
│       ├── validators.dart         # Input validation (TODO)
│       └── formatters.dart         # Date/time formatting (TODO)
├── pubspec.yaml                    # Dependencies
├── android/                        # Android-specific files
├── ios/                            # iOS-specific files
└── web/                            # Web-specific files
```

## 🔐 **Security Architecture**

### Key Management
- **Identity Keys**: Long-term Ed25519 keys for user identity
- **Signed Prekeys**: X25519 keys signed by identity key
- **One-time Prekeys**: X25519 keys for forward secrecy
- **Session Keys**: Derived from X3DH key agreement

### Storage
- **Private Keys**: Stored in Android Keystore/iOS Keychain
- **Session State**: Encrypted and stored securely
- **Public Keys**: Retrieved from backend when needed

### Encryption Flow
1. **Key Generation**: Create identity + prekeys on registration
2. **Key Exchange**: X3DH handshake for new conversations
3. **Message Encryption**: Double Ratchet (simplified version)
4. **Forward Secrecy**: One-time prekeys consumed after use

## 📱 **Current Implementation Status**

### ✅ **Completed**
- Flutter project setup with dependencies
- Core data models (User, Message, Conversation, PrekeyBundle)
- API service for backend communication
- Secure storage service for private keys
- Basic cryptographic functions (X3DH, encryption)

### 🚧 **Next Steps**
1. **Authentication Service**: Login/logout state management
2. **Socket Service**: Real-time messaging with Socket.IO
3. **UI Screens**: Login, chat list, individual chat
4. **Double Ratchet**: Full Signal Protocol implementation
5. **Testing**: Unit tests for crypto functions

## 🔧 **Dependencies**

### Core
- `flutter`: ^3.24.3
- `cryptography`: ^2.7.0 - Cryptographic operations
- `flutter_secure_storage`: ^9.2.2 - Secure key storage

### Networking
- `http`: ^1.2.1 - REST API calls
- `socket_io_client`: ^2.0.3+1 - Real-time messaging

### UI & State
- `provider`: ^6.1.2 - State management
- `google_fonts`: ^6.2.1 - Typography
- `flutter_chat_ui`: ^1.6.12 - Chat interface components

### Utils
- `uuid`: ^4.4.0 - Unique identifiers
- `intl`: ^0.19.0 - Internationalization
- `crypto`: ^3.0.3 - Hashing functions

## 🔒 **Security Features**

### Implemented
- X25519 key agreement for shared secrets
- Ed25519 signatures for key authentication
- AES-GCM encryption for messages
- Secure storage for private keys

### Planned
- Double Ratchet protocol for forward secrecy
- Key fingerprint verification (QR codes)
- Disappearing messages
- Screenshot protection
- Session management

## 🚀 **Development Commands**

```bash
# Run the app
flutter run

# Install dependencies
flutter pub get

# Check for issues
flutter analyze

# Run tests
flutter test

# Build for production
flutter build apk    # Android
flutter build ios    # iOS
```

## 📋 **Environment Setup**

### Android
- Minimum SDK: 21 (Android 5.0)
- Target SDK: 34
- Permissions: Internet, Storage

### iOS
- Minimum iOS: 12.0
- Keychain access for secure storage
- Network permissions

### Development
- Flutter SDK 3.24+
- Dart 3.9+
- VS Code with Flutter extension
- Android Studio/Xcode for device testing
