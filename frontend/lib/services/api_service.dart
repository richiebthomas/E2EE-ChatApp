import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import '../models/message.dart';
import '../models/prekey_bundle.dart';
import '../models/conversation.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, [this.statusCode]);

  @override
  String toString() => 'ApiException: $message (Status: $statusCode)';
}

class AuthResponse {
  final User user;
  final String token;

  const AuthResponse({required this.user, required this.token});

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      user: User.fromJson(json['user']),
      token: json['token'],
    );
  }
}

class ApiService {
  static const String baseUrl = 'http://192.168.1.105:3000/api';
  String? _authToken;
  User? _currentUser;

  // Getters
  String? get authToken => _authToken;
  User? get currentUser => _currentUser;
  bool get isAuthenticated => _authToken != null && _currentUser != null;

  // Set authentication
  void setAuth(String token, User user) {
    _authToken = token;
    _currentUser = user;
  }

  // Clear authentication
  void clearAuth() {
    _authToken = null;
    _currentUser = null;
  }

  // HTTP headers with auth
  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
    };
    
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    
    return headers;
  }

  // Handle HTTP response
  Map<String, dynamic> _handleResponse(http.Response response) {
    final data = json.decode(response.body);
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    } else {
      final message = data['error'] ?? 'Unknown error occurred';
      throw ApiException(message, response.statusCode);
    }
  }

  // Auth endpoints
  Future<AuthResponse> register({
    required String username,
    required String email,
    required String password,
    required String identityPubkey,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: _headers,
      body: json.encode({
        'username': username,
        'email': email,
        'password': password,
        'identityPubkey': identityPubkey,
      }),
    );

    final data = _handleResponse(response);
    return AuthResponse.fromJson(data);
  }

  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: _headers,
      body: json.encode({
        'email': email,
        'password': password,
      }),
    );

    final data = _handleResponse(response);
    return AuthResponse.fromJson(data);
  }

  Future<User> verifyToken() async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/verify'),
      headers: _headers,
    );

    final data = _handleResponse(response);
    return User.fromJson(data['user']);
  }

  // Prekey endpoints
  Future<void> uploadPrekeys({
    required String signedPrekey,
    required String prekeySignature,
    required int keyId,
    required List<String> oneTimePrekeys,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/prekeys/upload'),
      headers: _headers,
      body: json.encode({
        'signedPrekey': signedPrekey,
        'prekeySignature': prekeySignature,
        'keyId': keyId,
        'oneTimePrekeys': oneTimePrekeys,
      }),
    );

    _handleResponse(response);
  }

  Future<PrekeyBundle> getPrekeyBundle(String userId) async {
    if (userId.isEmpty) {
      throw const ApiException('Invalid user id for prekey bundle request');
    }
    final response = await http.get(
      Uri.parse('$baseUrl/prekeys/$userId'),
      headers: _headers,
    );

    final data = _handleResponse(response);
    return PrekeyBundle.fromJson(data);
  }

  Future<Map<String, int>> getPrekeyCount() async {
    final response = await http.get(
      Uri.parse('$baseUrl/prekeys/count/mine'),
      headers: _headers,
    );

    final data = _handleResponse(response);
    return {
      'signedPrekeys': data['signedPrekeys'],
      'oneTimePrekeys': data['oneTimePrekeys'],
    };
  }

  // Upload only additional one-time prekeys
  Future<int> uploadOneTimePrekeys(List<String> oneTimePrekeys) async {
    final response = await http.post(
      Uri.parse('$baseUrl/prekeys/otp/bulk'),
      headers: _headers,
      body: json.encode({
        'oneTimePrekeys': oneTimePrekeys,
      }),
    );

    final data = _handleResponse(response);
    return (data['startKeyId'] as num?)?.toInt() ?? 0;
  }

  // Message endpoints
  Future<String> sendMessage({
    required String recipientId,
    required String ciphertext,
    String messageType = 'REGULAR',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/messages/send'),
      headers: _headers,
      body: json.encode({
        'recipientId': recipientId,
        'ciphertext': ciphertext,
        'messageType': messageType,
      }),
    );

    final data = _handleResponse(response);
    return data['messageId'];
  }

  Future<List<Message>> getOfflineMessages() async {
    if (_currentUser == null) throw ApiException('Not authenticated');
    
    final response = await http.get(
      Uri.parse('$baseUrl/messages/offline'),
      headers: _headers,
    );

    final data = _handleResponse(response);
    final messages = data['messages'] as List;
    
    return messages
        .map((msg) => Message.fromJson(msg, _currentUser!.id))
        .toList();
  }

  Future<List<Message>> getConversation(String userId, {int limit = 50}) async {
    if (_currentUser == null) throw ApiException('Not authenticated');
    
    final response = await http.get(
      Uri.parse('$baseUrl/messages/conversation/$userId?limit=$limit'),
      headers: _headers,
    );

    final data = _handleResponse(response);
    final messages = data['messages'] as List;
    
    return messages
        .map((msg) => Message.fromJson(msg, _currentUser!.id))
        .toList();
  }

  Future<void> acknowledgeMessage(String messageId) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/messages/$messageId/acknowledge'),
      headers: _headers,
    );

    _handleResponse(response);
  }

  // User endpoints
  Future<User> getCurrentUser() async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/me'),
      headers: _headers,
    );

    final data = _handleResponse(response);
    return User.fromJson(data['user']);
  }

  // Keys backup APIs
  Future<void> uploadKeyBackup({
    required String backup,
    required String salt,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/users/keys/backup'),
      headers: _headers,
      body: json.encode({ 'backup': backup, 'salt': salt }),
    );
    _handleResponse(response);
  }

  Future<Map<String, String>?> getKeyBackup() async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/keys/backup'),
      headers: _headers,
    );
    if (response.statusCode == 404) return null;
    final data = _handleResponse(response);
    return { 'backup': data['backup'] as String, 'salt': data['salt'] as String? ?? '' };
  }

  // Rotate identity public key and clear prekeys server-side
  Future<void> rotateIdentity(String identityPubkey) async {
    final response = await http.post(
      Uri.parse('$baseUrl/users/identity/rotate'),
      headers: _headers,
      body: json.encode({ 'identityPubkey': identityPubkey }),
    );
    _handleResponse(response);
  }

  Future<List<User>> searchUsers(String query) async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/search?q=${Uri.encodeComponent(query)}'),
      headers: _headers,
    );

    final data = _handleResponse(response);
    final users = data['users'] as List;
    
    return users.map((user) => User.fromJson(user)).toList();
  }

  Future<User> getUser(String userId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/$userId'),
      headers: _headers,
    );

    final data = _handleResponse(response);
    return User.fromJson(data['user']);
  }

  Future<List<Conversation>> getRecentConversations() async {
    if (_currentUser == null) throw ApiException('Not authenticated');
    
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users/conversations/recent'),
        headers: _headers,
      );

      final data = _handleResponse(response);
      final conversations = data['conversations'] as List;
      
      return conversations
          .map((conv) {
            try {
              return Conversation.fromJson(conv, _currentUser!.id);
            } catch (e) {
              print('Error parsing conversation: $e');
              print('Conversation data: $conv');
              throw ApiException('Failed to parse conversation data: $e');
            }
          })
          .toList();
    } catch (e) {
      print('Error loading conversations: $e');
      throw ApiException('Failed to load conversations: $e');
    }
  }
}
