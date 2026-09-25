import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'websocket_service.dart';
import 'local_storage_service.dart';
import '../utils/app_log.dart';

class AuthService {
  static const String baseUrl = 'https://vortexlabsofficial.com/device_app';

  static Map<String, dynamic>? currentUser;
  static String? _token;

  static bool get isLoggedIn => currentUser != null;

  // ============================================================
  // CREDENTIAL STORAGE
  // ============================================================
  // The account password is kept so the app can silently re-login when the
  // JWT expires (see _silentRefresh). It used to live in SharedPreferences,
  // which is plain XML on disk — readable on a rooted device and through some
  // backup paths. It now lives in flutter_secure_storage, which on Android
  // encrypts with AES-GCM under a key wrapped by the hardware KeyStore.
  //
  // STILL NOT IDEAL: holding the password at all is weaker than holding a
  // server-issued refresh token, because a refresh token can be revoked and
  // scoped while a password cannot. Moving to one needs a server endpoint —
  // worth doing, and this class is the only thing that would change.
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  static const String _kUsername = 'saved_username';
  static const String _kPassword = 'saved_password';

  /// Moves credentials written by older builds out of SharedPreferences and
  /// into secure storage, then deletes the plaintext copies. Safe to call on
  /// every launch — it no-ops once the prefs keys are gone.
  static Future<void> _migrateLegacyCredentials(SharedPreferences prefs) async {
    final legacyUser = prefs.getString(_kUsername);
    final legacyPass = prefs.getString(_kPassword);
    if (legacyUser == null && legacyPass == null) return;

    if (legacyUser != null) {
      await _secure.write(key: _kUsername, value: legacyUser);
      await prefs.remove(_kUsername);
    }
    if (legacyPass != null) {
      await _secure.write(key: _kPassword, value: legacyPass);
      await prefs.remove(_kPassword);
    }
    logD('🔑 Migrated saved credentials out of SharedPreferences');
  }

  static Future<void> _saveCredentials(String username, String password) async {
    await _secure.write(key: _kUsername, value: username);
    await _secure.write(key: _kPassword, value: password);
  }

  static Future<void> _clearCredentials() async {
    await _secure.delete(key: _kUsername);
    await _secure.delete(key: _kPassword);
  }

  /// True when a silent refresh has something to work with.
  static Future<bool> get hasSavedCredentials async =>
      await _secure.read(key: _kUsername) != null;

  // ============================================================
  // JWT TOKEN EXPIRY CHECK
  // ============================================================
  /// Decode the JWT payload and check if it's expired or close to expiry.
  /// Returns true if the token is expired or will expire within 5 minutes.
  /// JWT format: header.payload.signature (base64url encoded)
  static bool isTokenExpired() {
    if (_token == null) return true;
    try {
      final parts = _token!.split('.');
      if (parts.length != 3) return true;

      // Decode the payload (middle part)
      // base64Url.normalize adds padding if needed
      final payloadStr = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final payload = jsonDecode(payloadStr);

      // Check 'exp' claim (Unix timestamp in seconds)
      final exp = payload['exp'];
      if (exp == null) return false; // No expiry = never expires

      final expiryDate = DateTime.fromMillisecondsSinceEpoch(
        (exp is int ? exp : int.parse(exp.toString())) * 1000,
      );

      // Consider expired if less than 5 minutes remaining
      final now = DateTime.now();
      final isExpired = now.isAfter(
        expiryDate.subtract(const Duration(minutes: 5)),
      );

      if (isExpired) {
        logD("🔑 Token expires at: $expiryDate (now: $now) → EXPIRED/EXPIRING");
      } else {
        logD("🔑 Token expires at: $expiryDate (now: $now) → still valid");
      }

      return isExpired;
    } catch (e) {
      logD("⚠️ Token decode error: $e — treating as expired");
      return true;
    }
  }

  // ============================================================
  // SILENT TOKEN REFRESH
  // ============================================================
  /// Try to get a fresh token using saved credentials.
  /// Returns true if refresh succeeded, false if user must re-login manually.
  static Future<bool> _silentRefresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUsername = await _secure.read(key: _kUsername);
      final savedPassword = await _secure.read(key: _kPassword);

      if (savedUsername == null || savedPassword == null) {
        logD("🔑 No saved credentials — cannot silent refresh");
        return false;
      }

      logD("🔑 Silent refresh: logging in as $savedUsername...");

      final response = await http.post(
        Uri.parse('$baseUrl/login.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': savedUsername,
          'password': savedPassword,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Silent refresh timed out');
        },
      );

      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        currentUser = data['user'];
        _token = data['access_token'];

        // Save the new token
        await prefs.setString('access_token', _token!);
        await prefs.setString('user_data', jsonEncode(currentUser));

        logD("✅ Silent refresh succeeded — new token saved");
        return true;
      } else {
        logD("❌ Silent refresh failed: ${data['message']}");
        // Credentials may have been changed by admin — force manual login
        return false;
      }
    } catch (e) {
      logD("❌ Silent refresh error: $e");
      // Network error — might be in AP mode, don't force logout
      // Just continue with old token, WebSocket will fail gracefully
      return false;
    }
  }

  // ============================================================
  // 1. Check if user is already logged in (app start)
  // ============================================================
  /// IMPORTANT: This must NOT block app startup.
  /// When phone is connected to ESP32 hotspot (no internet),
  /// WebSocket.connect() would hang forever. So we fire-and-forget it.
  static Future<bool> checkLoginStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Anyone upgrading from a build that stored the password in plain
      // SharedPreferences gets it moved into encrypted storage here, and the
      // plaintext copy deleted. Runs before anything reads credentials.
      await _migrateLegacyCredentials(prefs);

      final token = prefs.getString('access_token');
      final userDataString = prefs.getString('user_data');

      if (token != null && userDataString != null) {
        _token = token;
        currentUser = jsonDecode(userDataString);

        // ✅ CHECK TOKEN EXPIRY
        if (isTokenExpired()) {
          logD("🔑 Token expired — attempting silent refresh...");

          final refreshed = await _silentRefresh();
          if (!refreshed) {
            // Could not refresh (no saved creds, or server rejected, or no internet)
            // If no internet (AP mode), continue with expired token — WebSocket will fail
            // but the app can still work in direct ESP32 mode.
            // Check if we have saved credentials at all:
            final hasCreds = await hasSavedCredentials;
            if (!hasCreds) {
              // No saved credentials → must force manual login
              logD("🔑 No saved credentials — forcing manual login");
              await _clearSession();
              return false;
            }
            // Has credentials but refresh failed (likely no internet / AP mode)
            // Continue — app will work in offline/direct mode
            logD("🔑 Refresh failed but has creds — continuing in offline mode");
          } else {
            logD("✅ login successful for: ${currentUser!['name']}");
          }
        } else {
          logD("✅ Auto-login successful for: ${currentUser!['name']}");
        }

        // Fire-and-forget: try server WebSocket in background
        // Do NOT await — this lets the app start instantly
        // even when connected to ESP32 hotspot (no internet)
        WebSocketService.connect().then((connected) {
          if (connected) {
            logD("🔌 WS: Background connect succeeded");
          } else {
            logD("🔌 WS: Background connect failed (offline mode)");
          }
        }).catchError((e) {
          logD("🔌 WS: Background connect error: $e");
        });

        return true;
      }
    } catch (e) {
      logD("❌ Error restoring session: $e");
    }
    return false;
  }

  // ============================================================
  // 2. Login and Save Token
  // ============================================================
  static Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        currentUser = data['user'];
        _token = data['access_token'];

        // Never log the token itself — a JWT in a log line is a live session.
        logD("🔑 Login OK, token acquired (${_token!.length} chars)");

        // Save to phone storage
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', _token!);
        await prefs.setString('user_data', jsonEncode(currentUser));

        // Credentials go to encrypted storage, never SharedPreferences.
        await _saveCredentials(username, password);

        // Connect WebSocket after login (this is fine to await here
        // because login requires internet anyway)
        await WebSocketService.connect();
      }

      return data;
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: $e',
      };
    }
  }

  // ============================================================
  // 2b. Change Password (REST API)
  // ============================================================
  /// Changes the account password via change_password.php.
  /// On success, updates saved_password in SharedPreferences so silent
  /// token refresh keeps working — otherwise the next token expiry would
  /// fail to refresh and force a manual re-login.
  static Future<Map<String, dynamic>> changePassword(
    String oldPassword,
    String newPassword,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      final response = await http.post(
        Uri.parse('$baseUrl/change_password.php'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'old_password': oldPassword,
          'new_password': newPassword,
        }),
      );

      logD("🔑 Change Password Response: ${response.body}");

      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        // CRITICAL: keep the stored password in sync for silent refresh,
        // otherwise the next token expiry forces a manual re-login.
        await _secure.write(key: _kPassword, value: newPassword);
        logD("✅ Password changed — stored credential updated");
      }

      return data;
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: $e',
      };
    }
  }

  // ============================================================
  // 3. Logout and Clear Data
  // ============================================================
  static Future<void> logout() async {
    // Disconnect WebSocket first
    WebSocketService.disconnect();

    // Clear cached device list
    await LocalStorageService.clearCache();

    currentUser = null;
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    // prefs.clear() cannot reach the encrypted store — wipe it explicitly, or
    // the next user of this phone inherits the previous account's password.
    await _clearCredentials();
    logD("✅ Logged out, WebSocket disconnected & cache cleared");
  }

  // ============================================================
  // INTERNAL: Clear session without clearing saved credentials
  // ============================================================
  /// Used when token expired and refresh failed.
  /// Clears token and user data but keeps credentials for next attempt.
  static Future<void> _clearSession() async {
    WebSocketService.disconnect();
    currentUser = null;
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('user_data');
    // NOTE: We do NOT remove saved_username/saved_password here
    // so that login screen could potentially pre-fill them
    logD("🔑 Session cleared (credentials kept for next login)");
  }

  // ============================================================
  // PUBLIC: Force refresh token (call from anywhere)
  // ============================================================
  /// Call this when WebSocket gets rejected or any API returns 401.
  /// Returns true if refresh succeeded and WebSocket reconnected.
  static Future<bool> refreshTokenAndReconnect() async {
    logD("🔑 refreshTokenAndReconnect called...");
    final refreshed = await _silentRefresh();
    if (refreshed) {
      // Reconnect WebSocket with new token
      // Use skipExpiryCheck: true to avoid loop
      // (connect would see token is fresh and not call refresh again anyway,
      //  but this is a safety guard)
      WebSocketService.disconnect();
      final connected = await WebSocketService.connect(skipExpiryCheck: true);
      logD("🔌 WS reconnect after refresh: $connected");
      return connected;
    }
    return false;
  }
}