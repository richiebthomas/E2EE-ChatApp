import 'package:flutter/foundation.dart';
import '../models/user.dart';
import 'api_service.dart';
import 'secure_storage_service.dart';
import 'crypto_service.dart';

enum AuthState {
  initial,
  loading,
  authenticated,
  unauthenticated,
  error,
}

class AuthService extends ChangeNotifier {
  final ApiService _apiService;
  final SecureStorageService _storageService;

  AuthState _state = AuthState.initial;
  User? _currentUser;
  String? _errorMessage;

  AuthService(this._apiService, this._storageService);

  // Getters
  AuthState get state => _state;
  User? get currentUser => _currentUser;
  String? get errorMessage => _errorMessage;
  String? get authToken => _apiService.authToken;
  bool get isAuthenticated => _state == AuthState.authenticated;
  bool get isLoading => _state == AuthState.loading;

  // Initialize auth service (check for existing session)
  Future<void> initialize() async {
    try {
      _setState(AuthState.loading);

      // Check for stored auth token
      final token = await _storageService.getAuthToken();
      if (token == null) {
        _setState(AuthState.unauthenticated);
        return;
      }

      // Verify token with backend
      _apiService.setAuth(token, User(
        id: '', username: '', email: '', createdAt: DateTime.now(),
      ));

      final user = await _apiService.verifyToken();
      
      // Load complete user data
      final userData = await _storageService.getUserData();
      if (userData != null) {
        _currentUser = User.fromJson(userData);
      } else {
        _currentUser = user;
        await _storageService.saveUserData(user.toJson());
      }

      _apiService.setAuth(token, _currentUser!);
      _setState(AuthState.authenticated);

    } catch (e) {
      debugPrint('Auth initialization failed: $e');
      await _clearAuth();
      _setState(AuthState.unauthenticated);
    }
  }

  // Register new user
  Future<void> register({
    required String username,
    required String email,
    required String password,
  }) async {
    try {
      _setState(AuthState.loading);

      // Generate identity key pair
      final identityKeys = await CryptoService.generateIdentityKeyPair();
      
      // Register with backend
      final authResponse = await _apiService.register(
        username: username,
        email: email,
        password: password,
        identityPubkey: identityKeys['publicKey']!,
      );

      // Store auth data
      await Future.wait([
        _storageService.saveAuthToken(authResponse.token),
        _storageService.saveUserData(authResponse.user.toJson()),
        _storageService.saveIdentityKeyPair(
          privateKey: identityKeys['privateKey']!,
          publicKey: identityKeys['publicKey']!,
        ),
      ]);

      // Set authenticated state first so API calls include auth token
      _currentUser = authResponse.user;
      _apiService.setAuth(authResponse.token, _currentUser!);
      
      // Generate and upload prekeys (now with proper auth)
      await _generateAndUploadPrekeys();
      
      _setState(AuthState.authenticated);

    } catch (e) {
      _setError('Registration failed: ${e.toString()}');
    }
  }

  // Login existing user
  Future<void> login({
    required String email,
    required String password,
  }) async {
    try {
      _setState(AuthState.loading);

      // Login with backend
      final authResponse = await _apiService.login(
        email: email,
        password: password,
      );

      // Store auth data
      await Future.wait([
        _storageService.saveAuthToken(authResponse.token),
        _storageService.saveUserData(authResponse.user.toJson()),
      ]);

      // Check if we need to generate keys (shouldn't happen for existing users)
      final hasKeys = await _storageService.hasIdentityKeys();
      if (!hasKeys) {
        debugPrint('Warning: Existing user missing identity keys. This should not happen.');
        // In a real app, you might want to handle this case differently
      }

      // Set authenticated state
      _currentUser = authResponse.user;
      _apiService.setAuth(authResponse.token, _currentUser!);
      _setState(AuthState.authenticated);

      // Ensure identity keys exist locally; if missing, rotate on server and upload fresh prekeys
      final missingKeys = !(await _storageService.hasIdentityKeys());
      if (missingKeys) {
        // Regenerate identity
        final identityKeys = await CryptoService.generateIdentityKeyPair();
        await _storageService.saveIdentityKeyPair(
          privateKey: identityKeys['privateKey']!,
          publicKey: identityKeys['publicKey']!,
        );

        // Rotate identity on server
        await _apiService.rotateIdentity(identityKeys['publicKey']!);

        // Generate and upload fresh prekeys
        await _generateAndUploadPrekeys();
      }

    } catch (e) {
      _setError('Login failed: ${e.toString()}');
    }
  }

  // Logout user
  Future<void> logout() async {
    try {
      _setState(AuthState.loading);
      await _clearAuth();
      _setState(AuthState.unauthenticated);
    } catch (e) {
      _setError('Logout failed: ${e.toString()}');
    }
  }

  // Generate and upload prekeys to backend
  Future<void> _generateAndUploadPrekeys() async {
    try {
      // Get identity keys
      final identityKeys = await _storageService.getIdentityKeyPair();
      if (identityKeys == null) {
        throw Exception('Identity keys not found');
      }

      // Generate signed prekey
      final signedPrekey = await CryptoService.generateSignedPrekeyPair(
        identityPrivateKey: identityKeys['privateKey']!,
        keyId: 1,
      );

      // Generate one-time prekeys
      const prekeyCount = 50;
      final oneTimePrekeys = await CryptoService.generateOneTimePrekeys(prekeyCount);

      // Store private keys locally
      await Future.wait([
        _storageService.saveSignedPrekeyPair(
          privateKey: signedPrekey['privateKey']!,
          publicKey: signedPrekey['publicKey']!,
          keyId: signedPrekey['keyId'],
        ),
        ...oneTimePrekeys.map((otp) => _storageService.saveOneTimePrekeyPrivate(
          keyId: otp['keyId'],
          privateKey: otp['privateKey']!,
        )),
      ]);

      // Upload public keys to backend
      await _apiService.uploadPrekeys(
        signedPrekey: signedPrekey['publicKey']!,
        prekeySignature: signedPrekey['signature']!,
        keyId: signedPrekey['keyId'],
        oneTimePrekeys: oneTimePrekeys.map((otp) => otp['publicKey']! as String).toList(),
      );

      debugPrint('Successfully generated and uploaded prekeys');

    } catch (e) {
      debugPrint('Failed to generate/upload prekeys: $e');
      throw Exception('Key generation failed: $e');
    }
  }

  // Refresh prekeys if running low
  Future<void> refreshPrekeysIfNeeded() async {
    try {
      if (!isAuthenticated) return;

      final prekeyCount = await _apiService.getPrekeyCount();
      const minimumPrekeys = 10;

      if (prekeyCount['oneTimePrekeys']! < minimumPrekeys) {
        debugPrint('Refreshing one-time prekeys (current: ${prekeyCount['oneTimePrekeys']})');
        
        // Generate new one-time prekeys
        const newPrekeyCount = 50;
        final newPrekeys = await CryptoService.generateOneTimePrekeys(newPrekeyCount);

        // Upload to backend using OTP-only endpoint and record starting key id
        final startKeyId = await _apiService.uploadOneTimePrekeys(
          newPrekeys.map((otp) => otp['publicKey']! as String).toList(),
        );

        // Store private keys using global key ids assigned by server
        for (int i = 0; i < newPrekeys.length; i++) {
          final globalId = startKeyId + i;
          await _storageService.saveOneTimePrekeyPrivate(
            keyId: globalId,
            privateKey: newPrekeys[i]['privateKey']!,
          );
        }

        debugPrint('Uploaded ${newPrekeys.length} OTPs, stored with ids [$startKeyId..${startKeyId + newPrekeys.length - 1}]');

        debugPrint('Successfully refreshed prekeys');
      }
    } catch (e) {
      debugPrint('Failed to refresh prekeys: $e');
    }
  }

  // Clear authentication data
  Future<void> _clearAuth() async {
    await _storageService.clearAuthToken();
    await _storageService.clearUserData();
    _apiService.clearAuth();
    _currentUser = null;
    _errorMessage = null;
  }

  // Set state and notify listeners
  void _setState(AuthState newState) {
    _state = newState;
    if (newState != AuthState.error) {
      _errorMessage = null;
    }
    notifyListeners();
  }

  // Set error state
  void _setError(String message) {
    _errorMessage = message;
    _state = AuthState.error;
    notifyListeners();
  }

  // Clear error
  void clearError() {
    if (_state == AuthState.error) {
      _setState(AuthState.unauthenticated);
    }
  }
}

