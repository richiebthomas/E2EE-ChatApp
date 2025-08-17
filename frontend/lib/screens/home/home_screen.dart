import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../utils/constants.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh prekeys when app starts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthService>().refreshPrekeysIfNeeded();
    });
  }

  Future<void> _handleLogout() async {
    final authService = context.read<AuthService>();
    
    // Show confirmation dialog
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await authService.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Implement user search
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Search feature coming soon!')),
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'settings':
                  // TODO: Navigate to settings
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Settings coming soon!')),
                  );
                  break;
                case 'logout':
                  _handleLogout();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('Settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Logout'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Consumer<AuthService>(
        builder: (context, authService, child) {
          final user = authService.currentUser;
          
          return Padding(
            padding: AppConstants.formPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Welcome Card
                Card(
                  child: Padding(
                    padding: AppConstants.formPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              child: Text(
                                user?.username.substring(0, 1).toUpperCase() ?? 'U',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppConstants.defaultPadding),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Welcome back!',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    user?.username ?? 'User',
                                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.verified_user,
                              color: AppConstants.encryptedColor,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppConstants.defaultPadding),
                        Container(
                          padding: const EdgeInsets.all(AppConstants.defaultPadding),
                          decoration: BoxDecoration(
                            color: AppConstants.encryptedColor.withOpacity(0.1),
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
                                  AppConstants.encryptionEnabledMessage,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppConstants.encryptedColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: AppConstants.largePadding),
                
                // Coming Soon Features
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'Chat Features Coming Soon',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppConstants.defaultPadding),
                      
                      Expanded(
                        child: ListView(
                          children: [
                            _buildFeatureCard(
                              context,
                              Icons.chat_bubble_outline,
                              'Conversations',
                              'Start secure chats with other users',
                              false,
                            ),
                            _buildFeatureCard(
                              context,
                              Icons.group_outlined,
                              'Group Chats',
                              'Multi-party encrypted conversations',
                              false,
                            ),
                            _buildFeatureCard(
                              context,
                              Icons.file_present_outlined,
                              'File Sharing',
                              'Send encrypted photos and documents',
                              false,
                            ),
                            _buildFeatureCard(
                              context,
                              Icons.timer_outlined,
                              'Disappearing Messages',
                              'Messages that auto-delete after time',
                              false,
                            ),
                            _buildFeatureCard(
                              context,
                              Icons.verified_outlined,
                              'Key Verification',
                              'Verify contacts with QR codes',
                              false,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Status Info
                Card(
                  child: Padding(
                    padding: AppConstants.formPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Account Status',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppConstants.smallPadding),
                        _buildStatusRow(context, 'User ID', user?.id ?? 'Unknown'),
                        _buildStatusRow(context, 'Email', user?.email ?? 'Unknown'),
                        _buildStatusRow(context, 'Member since', 
                          user?.createdAt.toString().split(' ')[0] ?? 'Unknown'),
                        _buildStatusRow(context, 'Encryption', 'Active', 
                          color: AppConstants.encryptedColor),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // TODO: Navigate to new chat screen
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('New chat feature coming soon!')),
          );
        },
        child: const Icon(Icons.add_comment),
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context,
    IconData icon,
    String title,
    String description,
    bool isAvailable,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppConstants.smallPadding),
      child: ListTile(
        leading: Icon(
          icon,
          color: isAvailable 
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        title: Text(title),
        subtitle: Text(description),
        trailing: isAvailable
          ? Icon(
              Icons.arrow_forward_ios,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Soon',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        onTap: isAvailable
          ? () {
              // TODO: Navigate to feature
            }
          : null,
      ),
    );
  }

  Widget _buildStatusRow(BuildContext context, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
