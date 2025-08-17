import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/secure_storage_service.dart';
import 'services/socket_service.dart';
import 'services/message_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/chat/chat_list_screen.dart';
import 'utils/constants.dart';

void main() {
  runApp(const EncryptedChatApp());
}

class EncryptedChatApp extends StatelessWidget {
  const EncryptedChatApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Core Services
        Provider<ApiService>(create: (_) => ApiService()),
        Provider<SecureStorageService>(create: (_) => SecureStorageService()),
        
        // Socket Service
        ChangeNotifierProvider<SocketService>(
          create: (_) => SocketService(),
        ),
        
        // Auth Service (depends on API and Storage)
        ChangeNotifierProvider<AuthService>(
          create: (context) => AuthService(
            context.read<ApiService>(),
            context.read<SecureStorageService>(),
          ),
        ),
        
        // Message Service (depends on API, Storage, and Socket)
        ChangeNotifierProvider<MessageService>(
          create: (context) => MessageService(
            context.read<ApiService>(),
            context.read<SecureStorageService>(),
            context.read<SocketService>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme.copyWith(
          textTheme: GoogleFonts.interTextTheme(),
        ),
        darkTheme: AppTheme.darkTheme.copyWith(
          textTheme: GoogleFonts.interTextTheme(
            ThemeData.dark().textTheme,
          ),
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    // Initialize auth service
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthService>().initialize();
    });
  }

  void _initializeSocket() {
    final authService = context.read<AuthService>();
    final socketService = context.read<SocketService>();
    
    if (authService.isAuthenticated && !socketService.isConnected) {
      socketService.connect(
        serverUrl: AppConstants.socketUrl,
        authToken: authService.authToken ?? '',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        switch (authService.state) {
          case AuthState.initial:
          case AuthState.loading:
            return const LoadingScreen();
          
          case AuthState.authenticated:
            _initializeSocket();
            return const ChatListScreen();
          
          case AuthState.unauthenticated:
          case AuthState.error:
            return const LoginScreen();
        }
      },
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App Logo
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.lock_outline,
                size: 60,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            
            const SizedBox(height: AppConstants.largePadding),
            
            Text(
              AppConstants.appName,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: AppConstants.smallPadding),
            
            Text(
              'End-to-end encrypted messaging',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            
            const SizedBox(height: AppConstants.largePadding * 2),
            
            // Loading Indicator
            CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
            
            const SizedBox(height: AppConstants.defaultPadding),
            
            Text(
              'Initializing secure connection...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            
            const SizedBox(height: AppConstants.largePadding * 2),
            
            // Security Notice
            Container(
              margin: const EdgeInsets.symmetric(horizontal: AppConstants.largePadding),
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(AppConstants.borderRadius),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.security,
                    color: AppConstants.encryptedColor,
                    size: 20,
                  ),
                  const SizedBox(width: AppConstants.smallPadding),
                  Expanded(
                    child: Text(
                      'Your privacy is protected by encryption',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}