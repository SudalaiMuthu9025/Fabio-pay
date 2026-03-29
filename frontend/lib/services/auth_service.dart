/// Fabio — Auth Service
///
/// Secure JWT token persistence using flutter_secure_storage.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

class AuthService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _tokenKey = 'fabio_access_token';

  /// Save JWT after login
  static Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  /// Retrieve stored JWT
  static Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  /// Delete JWT on logout
  static Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
  }

  /// Check if user has a valid (non-expired) token
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    if (token == null) return false;
    return !JwtDecoder.isExpired(token);
  }

  /// Decode token to get user info
  static Future<Map<String, dynamic>?> getDecodedToken() async {
    final token = await getToken();
    if (token == null) return null;
    return JwtDecoder.decode(token);
  }
}
