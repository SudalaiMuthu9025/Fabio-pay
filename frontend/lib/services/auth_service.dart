/// Fabio — Auth Service
///
/// Secure session token persistence using flutter_secure_storage.
/// Replaces JWT-based auth with server-side session tokens.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _tokenKey = 'fabio_session_token';
  static const _userKey = 'fabio_user_json';

  /// Save session token after login
  static Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  /// Retrieve stored session token
  static Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  /// Delete token on logout
  static Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }

  /// Check if user has a stored token
  /// (Server validates expiration, we just check presence)
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Save user info as JSON string for offline access
  static Future<void> saveUserJson(String json) async {
    await _storage.write(key: _userKey, value: json);
  }

  /// Get cached user JSON
  static Future<String?> getUserJson() async {
    return await _storage.read(key: _userKey);
  }
}
