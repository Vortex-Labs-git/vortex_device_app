import 'package:flutter/material.dart';
import '../controllers/device_repository.dart';
import '../services/auth_service.dart';
import '../theme/glass_theme.dart';
import '../widgets/glass/glass.dart';
import 'login/login_screen.dart';
import 'app_gate.dart';

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
          DeviceRepository.instance.reloadForLogin();
          // Re-run AppGate: a session exists now, so it advances to the
          // permission gate and then to MainScreen.
          appGateRevision.value++;
        },
      );
    }

    // If logged in, show profile
    return _buildProfileView();
  }

  // ---------------------------------------------------------------------------
  // Profile (UI v2): forest profile card, then grouped settings rows —
  // account info, Change password, Log out. Same data and actions as before.
  // ---------------------------------------------------------------------------
  Widget _buildProfileView() {
    final user = AuthService.currentUser!;
    final String name = (user['name'] ?? '').toString().trim();
    final String email = (user['email'] ?? '').toString().trim();
    final String phone = (user['contact'] ?? '').toString().trim();

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        // Clear the translucent bottom nav this tab scrolls under.
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Profile card
          ForestHeader(
            coverStatusBar: false,
            radius: GlassTokens.radiusLg,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: GlassTokens.gold,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    _initials(name),
                    style: const TextStyle(
                      fontFamily: GlassTokens.displayFont,
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      color: GlassTokens.onGold,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isNotEmpty ? name : 'User',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: GlassTokens.displayFont,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          color: Colors.white,
                        ),
                      ),
                      if (email.isNotEmpty)
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 2. Account info
          const SettingsLabel('Account info'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.person_outline_rounded,
                iconColor: GlassTokens.primary,
                iconBackground: GlassTokens.leafSoft,
                title: 'Username',
                subtitle: name.isNotEmpty ? name : 'N/A',
              ),
              SettingsRow(
                icon: Icons.mail_outline_rounded,
                iconColor: GlassTokens.water,
                iconBackground: GlassTokens.waterSoft,
                title: 'Email',
                subtitle: email.isNotEmpty ? email : 'N/A',
              ),
              SettingsRow(
                icon: Icons.phone_outlined,
                iconColor: GlassTokens.sun,
                iconBackground: GlassTokens.sunSoft,
                title: 'Phone',
                subtitle: phone.isNotEmpty ? phone : 'Not set',
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 3. Security
          const SettingsLabel('Security'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.lock_outline_rounded,
                iconColor: GlassTokens.textSecondary,
                iconBackground: GlassTokens.sunk,
                title: 'Change password',
                onTap: _handleChangePassword,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 4. Log out
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.logout_rounded,
                iconColor: GlassTokens.danger,
                iconBackground: GlassTokens.danger.withValues(alpha: 0.1),
                title: 'Log out',
                titleColor: GlassTokens.danger,
                onTap: _handleLogout,
                showChevron: false,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "Nimal Perera" → "NP", "nimal" → "N", "" → "U".
  static String _initials(String name) {
    final parts =
        name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    final String first = parts.first[0];
    final String last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  void _handleChangePassword() {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    bool isLoading = false;
    String? errorText;

    showGlassDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return GlassDialog(
              title: 'Change Password',
              icon: Icons.lock_reset,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: oldPasswordController,
                    obscureText: true,
                    decoration: glassInputDecoration(
                      labelText: 'Old Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPasswordController,
                    obscureText: true,
                    decoration: glassInputDecoration(
                      labelText: 'New Password',
                      prefixIcon: const Icon(Icons.lock_open_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: true,
                    decoration: glassInputDecoration(
                      labelText: 'Confirm New Password',
                      prefixIcon: const Icon(Icons.check_circle_outline),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: TextStyle(
                        color: Color.lerp(GlassTokens.danger, Colors.black, 0.25),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      isLoading ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                GlassButton(
                  label: 'Change Password',
                  fullWidth: false,
                  height: 44,
                  isLoading: isLoading,
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
                                  backgroundColor: GlassTokens.success,
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
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleLogout() {
    showGlassDialog(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: 'Logout',
        icon: Icons.logout,
        tint: GlassTokens.danger,
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: GlassTokens.textSecondary, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          GlassButton(
            label: 'Logout',
            color: GlassTokens.danger,
            fullWidth: false,
            height: 44,
            onPressed: () async {
              Navigator.pop(dialogContext); // Close dialog
              await AuthService.logout(); // Wait for logout to complete

              // Drop the old account's devices from memory too. logout()
              // only clears the disk cache; the repository singleton keeps
              // its in-memory list, which is what HomeScreen renders.
              DeviceRepository.instance.clearForLogout();

              if (mounted) {
                // Re-run AppGate: session exists now, so it moves to the permission
                // This ensures all pages (Home, User, etc.) rebuild with logged-out state
                // Send the app back through AppGate, which drops straight to
                // the login screen now that the session is gone.
                appGateRevision.value++;
              }
            },
          ),
        ],
      ),
    );
  }
}