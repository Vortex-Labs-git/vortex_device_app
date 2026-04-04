# AuthService — Complete Function Guide

**File:** `lib/services/auth_service.dart`  
**Purpose:** Handles everything related to user authentication — login, logout, session persistence, JWT token expiry detection, and silent token refresh.  
**Type:** Static class (no instances created, all methods and variables are static, shared across the entire app).

---

## How This File Fits in the App

```
User opens app
      │
      ▼
main.dart calls AuthService.checkLoginStatus()
      │
      ├── Token found & valid → Show MainScreen (Home, User, Manual, About)
      ├── Token found & expired → Silent refresh → Show MainScreen
      ├── Token found & expired & no internet → Continue in offline/direct mode
      └── No token found → Show LoginScreen
```

AuthService is the **first thing that runs** when the app starts. Every other screen depends on it — HomeScreen checks `AuthService.currentUser` for user info, WebSocketService reads the token from SharedPreferences (saved by AuthService), and UserScreen calls `AuthService.logout()`.

---

## Variables

### `currentUser` (Map?, static)
Holds the logged-in user's profile data returned by the server.

```
Example value:
{
  "id": "5",
  "name": "Narendra",
  "email": "narendra@example.com",
  "contact": "+94 77 123 4567"
}
```

- Set during `login()` or `checkLoginStatus()`
- Set to `null` on logout
- Used by UserScreen to display profile info
- Used by HomeScreen for user ID when requesting ESP32 data

### `_token` (String?, static, private)
The JWT access token string from the server.

```
Example value:
"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNSIsImV4cCI6MTcxMjM0NTY3OH0.abc123"
```

- Saved to SharedPreferences as `access_token`
- Used by WebSocketService in the `Authorization: Bearer` header
- Used by DeviceDetailScreen in REST API calls to `control_device.php`

### `isLoggedIn` (bool, getter)
Returns `true` if `currentUser` is not null. Used by `AppRoot` in `main.dart` to decide whether to show LoginScreen or MainScreen.

---

## Functions

---

### `isTokenExpired()` → bool

**What it does:**  
Checks if the JWT token has expired or is about to expire within 5 minutes.

**When it's called:**  
- At app startup inside `checkLoginStatus()`
- Before WebSocket connection inside `WebSocketService.connect()`

**How it works step by step:**

1. If `_token` is null → return `true` (no token = expired)
2. Split the token string by `.` (dots) — JWT has 3 parts: `header.payload.signature`
3. Take the middle part (payload) and decode it from base64
4. Parse the decoded string as JSON
5. Read the `exp` field — this is a Unix timestamp (seconds since 1970) set by the PHP server when the token was created
6. Convert `exp` to a DateTime
7. Subtract 5 minutes from the expiry time (safety buffer)
8. Compare with `DateTime.now()`
9. If now is after (expiry - 5 minutes) → return `true` (expired or expiring soon)

**Example:**
```
Token exp = 1712345678 → April 5, 2026 10:00:00 AM
Safety buffer = 5 minutes → Effective expiry = 9:55:00 AM
Current time = 9:56:00 AM → isTokenExpired() returns TRUE
Current time = 9:30:00 AM → isTokenExpired() returns FALSE
```

**Why the 5-minute buffer:**  
Without it, the token could expire in the middle of a REST API call or WebSocket connection attempt, causing a failure. The buffer ensures we refresh before that happens.

**If anything goes wrong** (malformed token, missing exp field, decode error) → returns `true` as a safe default. Better to refresh unnecessarily than to use a broken token.

---

### `_silentRefresh()` → Future\<bool\>

**What it does:**  
Gets a fresh JWT token from the server without the user doing anything. This is the core fix for the daily re-login problem.

**When it's called:**  
- By `checkLoginStatus()` when it detects an expired token at app startup
- By `refreshTokenAndReconnect()` when WebSocket gets rejected by the server

**How it works step by step:**

1. Read `saved_username` and `saved_password` from SharedPreferences
2. If either is missing → return `false` (can't refresh without credentials)
3. POST to `login.php` with the saved username and password (same as a normal login)
4. Wait up to 10 seconds for a response (timeout prevents hanging in AP mode)
5. If server returns `success: true`:
   - Update `currentUser` and `_token` with the fresh data
   - Save the new token to SharedPreferences
   - Return `true`
6. If server returns `success: false`:
   - Credentials were probably changed by admin
   - Return `false` (user must log in manually)
7. If network error or timeout:
   - Phone is probably on ESP32 hotspot (no internet)
   - Return `false` (don't crash, let app continue in offline mode)

**Where do saved_username and saved_password come from?**  
They are saved by the `login()` method the first time the user types their credentials on the login screen. They are stored in SharedPreferences on the phone at:
```
/data/data/com.vortexlabs.vortax_labs/shared_prefs/FlutterSharedPreferences.xml
```
They persist until the user logs out (which calls `prefs.clear()`).

---

### `checkLoginStatus()` → Future\<bool\>

**What it does:**  
Restores the user session when the app starts. Called once from `main.dart` before the UI loads.

**When it's called:**  
- Once, in `main()` at app startup

**Returns:**  
- `true` → User is logged in, show MainScreen
- `false` → User is not logged in, show LoginScreen

**How it works step by step:**

1. Read `access_token` and `user_data` from SharedPreferences
2. If both are missing → return `false` (first-time user, show login)
3. Set `_token` and `currentUser` from stored values
4. Call `isTokenExpired()`:
   - **Token is valid** → Skip to step 5
   - **Token is expired** → Call `_silentRefresh()`:
     - **Refresh succeeded** → Continue with fresh token
     - **Refresh failed, no saved credentials** → Call `_clearSession()`, return `false` (force login)
     - **Refresh failed, has saved credentials** → Continue anyway (probably AP mode, no internet — app works in direct ESP32 mode without a valid server token)
5. Print "Auto-login successful"
6. Fire-and-forget `WebSocketService.connect()`:
   - Do NOT await this call
   - If phone has internet → WebSocket connects in background
   - If phone is on ESP32 hotspot → WebSocket times out after 5 seconds, app doesn't hang
7. Return `true`

**Why fire-and-forget?**  
If we awaited `WebSocketService.connect()` and the phone was connected to the ESP32 hotspot (no internet), the app would freeze on the splash screen forever. By not awaiting, the app loads instantly and the WebSocket connects (or fails) in the background.

---

### `login(username, password)` → Future\<Map\>

**What it does:**  
Performs a full manual login. Called when the user taps "Sign In" on the login screen.

**When it's called:**  
- By `LoginScreen._handleLogin()` when user submits the login form

**Parameters:**  
- `username` — What the user typed in the username field
- `password` — What the user typed in the password field

**How it works step by step:**

1. POST to `login.php` with `{"username": "...", "password": "..."}`
2. If server returns `success: true`:
   - Set `currentUser` from `data['user']`
   - Set `_token` from `data['access_token']`
   - Save to SharedPreferences:
     - `access_token` → The JWT token
     - `user_data` → JSON string of user profile
     - `saved_username` → Raw username (for future silent refresh)
     - `saved_password` → Raw password (for future silent refresh)
   - Await `WebSocketService.connect()` (safe to await here because login requires internet)
3. Return the server response map

**Returns:**
```
Success: {"success": true, "user": {...}, "access_token": "eyJ..."}
Failure: {"success": false, "message": "Invalid credentials"}
Error:   {"success": false, "message": "Connection error: ..."}
```

**Why await WebSocket here but not in checkLoginStatus?**  
Because the user just completed a login which required internet. So we know internet is available. In `checkLoginStatus`, the phone might be on the ESP32 hotspot with no internet.

---

### `logout()` → Future\<void\>

**What it does:**  
Full cleanup — disconnects everything, clears all stored data.

**When it's called:**  
- By `UserScreen._handleLogout()` when user confirms logout

**How it works step by step:**

1. Call `WebSocketService.disconnect()` — close the server WebSocket
2. Call `LocalStorageService.clearCache()` — remove cached device list
3. Set `currentUser = null` and `_token = null`
4. Call `prefs.clear()` — removes **everything** from SharedPreferences:
   - `access_token` (JWT token)
   - `user_data` (user profile)
   - `saved_username` (login username)
   - `saved_password` (login password)
   - `cached_device_list` (device cache)
   - `device_list_last_sync` (cache timestamp)

**After logout:** The app navigates to a fresh `AppRoot` via `Navigator.pushAndRemoveUntil`. Since `AuthService.isLoggedIn` is now `false`, it shows the LoginScreen. The user must type their credentials again because `prefs.clear()` removed the saved username/password.

---

### `_clearSession()` → Future\<void\>

**What it does:**  
A softer version of logout. Clears the token and user data but **keeps saved credentials**.

**When it's called:**  
- By `checkLoginStatus()` when token is expired, refresh failed, and there are no saved credentials

**How it works step by step:**

1. Call `WebSocketService.disconnect()`
2. Set `currentUser = null` and `_token = null`
3. Remove only `access_token` and `user_data` from SharedPreferences
4. **Does NOT remove** `saved_username` and `saved_password`

**Why keep credentials?**  
If the user ends up on the login screen after this, their credentials are still in SharedPreferences. A future enhancement could pre-fill the login form with these saved values.

---

### `refreshTokenAndReconnect()` → Future\<bool\>

**What it does:**  
Public method that refreshes the token and reconnects the WebSocket. Can be called from anywhere in the app.

**When it's called:**  
- By `WebSocketService._handleAuthRejection()` when the server rejects the WebSocket connection due to an expired token
- By `WebSocketService.connect()` when it detects the token is expired before connecting

**How it works step by step:**

1. Call `_silentRefresh()` to get a fresh token
2. If refresh succeeded:
   - Call `WebSocketService.disconnect()` to close the old connection
   - Call `WebSocketService.connect(skipExpiryCheck: true)` to connect with fresh token
   - Return `true` if WebSocket connected
3. If refresh failed:
   - Return `false` (user may need to log in manually)

**Why `skipExpiryCheck: true`?**  
Without this flag, the following infinite loop would happen:
```
connect() → isTokenExpired() → true → refreshTokenAndReconnect()
→ _silentRefresh() → connect() → isTokenExpired() → true → refreshTokenAndReconnect()
→ ... forever
```
The flag tells `connect()` to skip the expiry check and use the token as-is. Since we just refreshed it, the token is guaranteed to be valid.

---

## Data Flow Summary

### First-Time Login
```
User types credentials → login() → POST login.php → Save token + credentials → Connect WebSocket
```

### Normal App Start (Token Valid)
```
checkLoginStatus() → Read token → isTokenExpired() = NO → Fire-and-forget WebSocket → Show MainScreen
```

### App Start After Token Expired (Has Internet)
```
checkLoginStatus() → Read token → isTokenExpired() = YES → _silentRefresh() → POST login.php
→ Fresh token saved → Fire-and-forget WebSocket → Show MainScreen (user sees nothing)
```

### App Start After Token Expired (On ESP32 Hotspot, No Internet)
```
checkLoginStatus() → Read token → isTokenExpired() = YES → _silentRefresh() → Timeout (no internet)
→ Has saved credentials? YES → Continue in offline mode → Show MainScreen with cached devices
```

### WebSocket Rejected Mid-Session
```
WebSocket onDone → Auth rejection detected → _handleAuthRejection() → refreshTokenAndReconnect()
→ _silentRefresh() → Fresh token → Reconnect WebSocket → Re-subscribe to device data
```

### Logout
```
logout() → Disconnect WebSocket → Clear cache → Clear ALL SharedPreferences → Show LoginScreen
```

---

## SharedPreferences Keys Used

| Key | Saved By | Cleared By | Purpose |
|-----|----------|------------|---------|
| `access_token` | `login()`, `_silentRefresh()` | `logout()`, `_clearSession()` | JWT token for API/WebSocket auth |
| `user_data` | `login()`, `_silentRefresh()` | `logout()`, `_clearSession()` | User profile JSON |
| `saved_username` | `login()` | `logout()` only | Username for silent refresh |
| `saved_password` | `login()` | `logout()` only | Password for silent refresh |

---

*Document Version: April 2026 — Vortex Labs Official*
