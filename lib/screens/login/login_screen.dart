import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass/glass.dart';
import 'widgets/login_field_art.dart';
import 'widgets/login_icon.dart';
import 'widgets/login_error.dart';
import 'widgets/login_username_field.dart';
import 'widgets/login_password_field.dart';
import 'widgets/login_button.dart';
import 'widgets/forgot_password_button.dart';

// =============================================================================
// LOGIN SCREEN
// =============================================================================
// Composes the login UI from small widgets in widgets/ and owns the screen
// state (controllers, loading flag, error message). Calls [onLoginSuccess]
// callback when authentication succeeds.
//
// Layout (UI v2): forest brand header with the logo, headline and field art,
// then the form on a ground-coloured panel that overlaps the header's edge.
// =============================================================================

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // ---------------------------------------------------------------------------
  // SECTION 1: STATE VARIABLES
  // ---------------------------------------------------------------------------

  // -- Text Controllers --
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  // -- UI State Flags --
  bool _isLoading = false;

  // -- Error State --
  String? _errorMessage;

  // ---------------------------------------------------------------------------
  // SECTION 2: LIFECYCLE METHODS
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // SECTION 3: LOGIN HANDLER
  // ---------------------------------------------------------------------------
  // Validates user input, calls AuthService.login(), and either fires the
  // success callback or shows an error message.
  // ---------------------------------------------------------------------------

  Future<void> _handleLogin() async {
    // Step 3.1: Read input values
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    // Step 3.2: Validate input is not empty
    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter username and password';
      });
      return;
    }

    // Step 3.3: Show loading state, clear previous errors
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Step 3.4: Call authentication service
    final result = await AuthService.login(username, password);

    // Step 3.5: Hide loading state
    setState(() {
      _isLoading = false;
    });

    // Step 3.6: Handle login result
    if (result['success'] == true) {
      widget.onLoginSuccess();
    } else {
      setState(() {
        _errorMessage = result['message'] ?? 'Login failed';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // SECTION 4: BUILD METHOD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Full-screen page with its own scaffold: the forest header runs behind
    // the status bar, and the form panel overlaps its rounded lower edge.
    // The scaffold resizes for the keyboard, so the form scrolls into view.
    return GlassScaffold(
      useSafeArea: false,
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: 8 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 4.1  Brand header: logo, headline, field art
            ForestHeader(
              radius: 0,
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const LoginIcon(),
                        const SizedBox(height: 18),
                        Text.rich(
                          const TextSpan(
                            children: [
                              TextSpan(text: 'Grow more with\n'),
                              TextSpan(
                                text: 'less water.',
                                style: TextStyle(color: GlassTokens.gold),
                              ),
                            ],
                          ),
                          style: const TextStyle(
                            fontFamily: GlassTokens.displayFont,
                            fontSize: 31,
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Control your valves, sensors and plugs from '
                          'anywhere on the farm.',
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.4,
                            color: Colors.white.withValues(alpha: 0.78),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                  const LoginFieldArt(),
                ],
              ),
            ),

            // 4.2  Form panel, pulled up over the header's bottom edge
            Transform.translate(
              offset: const Offset(0, -28),
              child: Container(
                decoration: const BoxDecoration(
                  color: GlassTokens.ground,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Error banner (only when there is an error)
                        if (_errorMessage != null)
                          LoginError(message: _errorMessage!),

                        // Username field
                        LoginUsernameField(controller: _usernameController),

                        const SizedBox(height: 14),

                        // Password field
                        LoginPasswordField(
                          controller: _passwordController,
                          onSubmitted: _handleLogin,
                        ),

                        // Forgot password link, right-aligned
                        const Align(
                          alignment: Alignment.centerRight,
                          child: ForgotPasswordButton(),
                        ),

                        const SizedBox(height: 6),

                        // Sign in button
                        LoginButton(
                          isLoading: _isLoading,
                          onPressed: _handleLogin,
                        ),

                        const SizedBox(height: 16),

                        const Text(
                          'New to Vortex? Contact Vortex Labs to set up '
                          'your account.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: GlassTokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
