import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../services/auth_service.dart';
import 'login/login_screen.dart';
import 'main/main_screen.dart';

class UserScreen extends StatefulWidget {
  const UserScreen({super.key});

  @override
  State<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  @override
  Widget build(BuildContext context) {
    // If not logged in, show login screen
    if (!AuthService.isLoggedIn) {
      return LoginScreen(
        onLoginSuccess: () {
          // Replace entire navigation stack with fresh MainScreen
          // This ensures HomeScreen re-initializes with WebSocket connected
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainScreen()),
            (route) => false,
          );
        },
      );
    }

    // If logged in, show profile
    return _buildProfileView();
  }

  Widget _buildProfileView() {
    final user = AuthService.currentUser!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 20),

          // 1. Profile Avatar (First letter of Name)
          CircleAvatar(
            radius: 50,
            backgroundColor: AppColors.primary,
            child: Text(
              // FIX: Use 'name' instead of 'username' or 'full_name'
              (user['name'] ?? 'U')[0].toUpperCase(),
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 2. User Name Display
          Text(
            // FIX: Use 'name'
            user['name'] ?? 'User',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),

          // 3. Email Display
          Text(
            // FIX: Use 'email' (This matches login.php line 92)
            user['email'] ?? '',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),

          const SizedBox(height: 24),

          // 4. Account Info Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ACCOUNT INFO',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // FIX ALL KEYS BELOW:
                  _buildInfoRow(Icons.person, 'Username', user['name'] ?? 'N/A'),
                  const Divider(),
                  _buildInfoRow(Icons.email, 'Email', user['email'] ?? 'N/A'),
                  const Divider(),
                  _buildInfoRow(Icons.phone, 'Phone', user['contact'] ?? 'Not set'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 5. Change Password Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _handleChangePassword(),
              icon: const Icon(Icons.lock_outline, color: Colors.white),
              label: const Text('Change Password',
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 6. Logout Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _handleLogout(),
              icon: const Icon(Icons.logout, color: Colors.white),
              label: const Text('Logout', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text(value, style: const TextStyle(fontSize: 16)),
            ],
          ),
        ],
      ),
    );
  }

  void _handleChangePassword() {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    bool isLoading = false;
    String? errorText;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Change Password'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: oldPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Old Password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: newPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm New Password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isLoading ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final oldPass = oldPasswordController.text.trim();
                          final newPass = newPasswordController.text.trim();
                          final confirmPass =
                              confirmPasswordController.text.trim();

                          // Validation
                          if (oldPass.isEmpty ||
                              newPass.isEmpty ||
                              confirmPass.isEmpty) {
                            setDialogState(
                                () => errorText = 'All fields are required');
                            return;
                          }
                          if (newPass.length < 6) {
                            setDialogState(() => errorText =
                                'New password must be at least 6 characters');
                            return;
                          }
                          if (newPass != confirmPass) {
                            setDialogState(() =>
                                errorText = 'New passwords do not match');
                            return;
                          }
                          if (newPass == oldPass) {
                            setDialogState(() => errorText =
                                'New password must differ from the old one');
                            return;
                          }

                          // Send request
                          setDialogState(() {
                            isLoading = true;
                            errorText = null;
                          });

                          final result = await AuthService.changePassword(
                              oldPass, newPass);

                          if (result['success'] == true) {
                            Navigator.pop(dialogContext);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(result['message'] ??
                                      'Password changed successfully'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } else {
                            setDialogState(() {
                              isLoading = false;
                              errorText = result['message'] ??
                                  'Failed to change password';
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Change Password'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              await AuthService.logout(); // Wait for logout to complete
              if (mounted) {
                // Replace entire navigation stack with fresh MainScreen
                // This ensures all pages (Home, User, etc.) rebuild with logged-out state
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const MainScreen()),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}