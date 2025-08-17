import 'package:flutter/material.dart';

class AppConstants {
  // App Info
  static const String appName = 'Encrypted Chat';
  static const String appVersion = '1.0.0';
  
  // API Configuration
  static const String baseUrl = 'http://192.168.1.103:3000/api';
  static const String socketUrl = 'http://192.168.1.103:3000';
  
  // Cryptographic Constants
  static const int prekeyGenerationCount = 50;
  static const int minimumPrekeyCount = 10;
  static const int maxMessageLength = 4096;
  
  // UI Constants
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;
  
  static const double borderRadius = 12.0;
  static const double smallBorderRadius = 8.0;
  static const double largeBorderRadius = 16.0;
  
  // Animation Durations
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 300);
  static const Duration longAnimation = Duration(milliseconds: 500);
  
  // Colors
  static const Color primaryColor = Color(0xFF2196F3);
  static const Color secondaryColor = Color(0xFF03DAC6);
  static const Color errorColor = Color(0xFFB00020);
  static const Color successColor = Color(0xFF4CAF50);
  static const Color warningColor = Color(0xFFFF9800);
  
  // Encryption Indicator Colors
  static const Color encryptedColor = Color(0xFF4CAF50);
  static const Color notEncryptedColor = Color(0xFFFF5722);
  static const Color keyExchangeColor = Color(0xFF2196F3);
  
  // Text Styles
  static const TextStyle headingStyle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
  );
  
  static const TextStyle subheadingStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );
  
  static const TextStyle bodyStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
  );
  
  static const TextStyle captionStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: Colors.grey,
  );
  
  // Form Constants
  static const EdgeInsets formPadding = EdgeInsets.all(defaultPadding);
  static const EdgeInsets inputPadding = EdgeInsets.symmetric(
    vertical: 12.0,
    horizontal: 16.0,
  );
  
  // Chat Constants
  static const double messageBubbleMaxWidth = 0.7;
  static const EdgeInsets messagePadding = EdgeInsets.symmetric(
    vertical: 8.0,
    horizontal: 12.0,
  );
  
  // Security Messages
  static const String encryptionEnabledMessage = '🔐 Messages are end-to-end encrypted';
  static const String keyExchangeMessage = '🔑 Establishing secure connection...';
  static const String messageSentMessage = '✓ Sent';
  static const String messageDeliveredMessage = '✓✓ Delivered';
  static const String messageReadMessage = '✓✓ Read';
  
  // Error Messages
  static const String networkErrorMessage = 'Network error. Please check your connection.';
  static const String serverErrorMessage = 'Server error. Please try again later.';
  static const String authErrorMessage = 'Authentication failed. Please login again.';
  static const String encryptionErrorMessage = 'Message encryption failed. Please try again.';
  static const String decryptionErrorMessage = 'Message decryption failed. This message may be corrupted.';
  
  // Storage Keys (for debugging - don't expose these in production)
  static const String debugStoragePrefix = 'encrypted_chat_debug_';
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppConstants.primaryColor,
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 4,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: AppConstants.inputPadding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        ),
        filled: true,
        contentPadding: AppConstants.inputPadding,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppConstants.primaryColor,
        brightness: Brightness.dark,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 4,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: AppConstants.inputPadding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        ),
        filled: true,
        contentPadding: AppConstants.inputPadding,
      ),
    );
  }
}
