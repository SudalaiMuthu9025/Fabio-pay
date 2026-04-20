/// Fabio — Auth Service
///
/// JWT token persistence using flutter_secure_storage.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'fabio_jwt_token';
  static const _userKey = 'fabio_user_json';
  static const _faceRegisteredKey = 'fabio_face_registered';

  /// Save JWT token
  static Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  /// Get stored JWT token
  static Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  /// Delete JWT token (logout)
  static Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
  }

  /// Save user JSON
  static Future<void> saveUserJson(String json) async {
    await _storage.write(key: _userKey, value: json);
  }

  /// Get stored user JSON
  static Future<String?> getUserJson() async {
    return await _storage.read(key: _userKey);
  }

  /// Save face registered flag
  static Future<void> setFaceRegistered(bool value) async {
    await _storage.write(key: _faceRegisteredKey, value: value.toString());
  }

  /// Check if face is registered locally
  static Future<bool> isFaceRegistered() async {
    final val = await _storage.read(key: _faceRegisteredKey);
    return val == 'true';
  }

  /// Clear all stored data
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
