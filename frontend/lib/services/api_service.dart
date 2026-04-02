/// Fabio — API Service
///
/// Dio-based REST client with automatic session token injection
/// and global 401 auto-logout handling.

import 'dart:convert';
import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../models/models.dart';
import 'auth_service.dart';

class ApiService {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ),
  )..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await AuthService.getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          handler.next(error);
        },
      ),
    );

  // ── Auth ──────────────────────────────────────────────────────────────

  static Future<String> login(String email, String password) async {
    final response = await _dio.post(ApiConfig.login, data: {
      'email': email,
      'password': password,
    });
    final token = response.data['session_token'];
    await AuthService.saveToken(token);
    // Fetch and cache user profile
    final user = await getMe();
    await AuthService.saveUserJson(jsonEncode(user.toJson()));
    return token;
  }

  static Future<User> register({
    required String email,
    required String fullName,
    required String password,
    required String pin,
  }) async {
    final response = await _dio.post(ApiConfig.register, data: {
      'email': email,
      'full_name': fullName,
      'password': password,
      'pin': pin,
    });
    return User.fromJson(response.data);
  }

  static Future<void> logout() async {
    try {
      await _dio.post(ApiConfig.logout);
    } catch (_) {
      // Best effort — clear local state regardless
    }
    await AuthService.deleteToken();
  }

  // ── User ──────────────────────────────────────────────────────────────

  static Future<User> getMe() async {
    final response = await _dio.get(ApiConfig.userMe);
    return User.fromJson(response.data);
  }

  static Future<User> updateProfile({String? fullName, String? email}) async {
    final data = <String, dynamic>{};
    if (fullName != null) data['full_name'] = fullName;
    if (email != null) data['email'] = email;
    final response = await _dio.patch(ApiConfig.userMe, data: data);
    final user = User.fromJson(response.data);
    await AuthService.saveUserJson(jsonEncode(user.toJson()));
    return user;
  }

  // ── Accounts ──────────────────────────────────────────────────────────

  static Future<List<BankAccount>> getAccounts() async {
    final response = await _dio.get(ApiConfig.accounts);
    return (response.data as List)
        .map((j) => BankAccount.fromJson(j))
        .toList();
  }

  static Future<BankAccount> createAccount({
    required String accountNumber,
    required String bankName,
    String? ifscCode,
    double balance = 0.0,
    String currency = 'INR',
  }) async {
    final data = <String, dynamic>{
      'account_number': accountNumber,
      'bank_name': bankName,
      'balance': balance.toString(),
      'currency': currency,
    };
    if (ifscCode != null) data['ifsc_code'] = ifscCode;
    final response = await _dio.post(ApiConfig.accounts, data: data);
    return BankAccount.fromJson(response.data);
  }

  static Future<void> deleteAccount(String accountId) async {
    await _dio.delete('${ApiConfig.accounts}$accountId');
  }

  // ── Security Settings ─────────────────────────────────────────────────

  static Future<SecuritySettings> getSecuritySettings() async {
    final response = await _dio.get(ApiConfig.security);
    return SecuritySettings.fromJson(response.data);
  }

  static Future<SecuritySettings> updateSecurity({
    double? thresholdAmount,
    String? pin,
    bool? biometricEnabled,
  }) async {
    final data = <String, dynamic>{};
    if (thresholdAmount != null) data['threshold_amount'] = thresholdAmount;
    if (pin != null) data['pin'] = pin;
    if (biometricEnabled != null) data['biometric_enabled'] = biometricEnabled;
    final response = await _dio.patch(ApiConfig.security, data: data);
    return SecuritySettings.fromJson(response.data);
  }

  // ── Transactions ──────────────────────────────────────────────────────

  static Future<TransferResult> initiateTransfer({
    required String fromAccountId,
    required String toAccountIdentifier,
    required double amount,
    String? pin,
    String? description,
  }) async {
    final data = <String, dynamic>{
      'from_account_id': fromAccountId,
      'to_account_identifier': toAccountIdentifier,
      'amount': amount,
    };
    if (pin != null) data['pin'] = pin;
    if (description != null) data['description'] = description;

    final response = await _dio.post(ApiConfig.transfer, data: data);
    return TransferResult.fromJson(response.data);
  }

  static Future<List<TransactionLog>> getTransactions() async {
    final response = await _dio.get(ApiConfig.transactions);
    return (response.data as List)
        .map((j) => TransactionLog.fromJson(j))
        .toList();
  }

  // ── Sessions ──────────────────────────────────────────────────────────

  static Future<List<SessionInfo>> getSessions() async {
    final response = await _dio.get(ApiConfig.sessions);
    return (response.data as List)
        .map((j) => SessionInfo.fromJson(j))
        .toList();
  }

  static Future<void> revokeSession(String sessionId) async {
    await _dio.delete('${ApiConfig.sessions}/$sessionId');
  }

  // ── Health ────────────────────────────────────────────────────────────

  static Future<bool> checkHealth() async {
    try {
      final response = await _dio.get(ApiConfig.health);
      return response.data['status'] == 'healthy';
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  ADMIN API
  // ═══════════════════════════════════════════════════════════════════════

  static Future<AdminDashboardStats> getAdminDashboard() async {
    final response = await _dio.get(ApiConfig.adminDashboard);
    return AdminDashboardStats.fromJson(response.data);
  }

  static Future<List<User>> getAdminUsers({
    String? role,
    bool? active,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{
      'limit': limit,
      'offset': offset,
    };
    if (role != null) params['role'] = role;
    if (active != null) params['active'] = active;
    if (search != null) params['search'] = search;

    final response = await _dio.get(ApiConfig.adminUsers, queryParameters: params);
    return (response.data as List).map((j) => User.fromJson(j)).toList();
  }

  static Future<User> changeUserRole(String userId, String newRole) async {
    final response = await _dio.patch(
      ApiConfig.adminChangeRole(userId),
      data: {'role': newRole},
    );
    return User.fromJson(response.data);
  }

  static Future<User> changeUserStatus(String userId, bool isActive) async {
    final response = await _dio.patch(
      ApiConfig.adminChangeStatus(userId),
      data: {'is_active': isActive},
    );
    return User.fromJson(response.data);
  }

  static Future<void> verifyBankAccount(String bankId) async {
    await _dio.put(ApiConfig.adminVerifyBank(bankId));
  }

  static Future<void> revokeUserSessions(String userId) async {
    await _dio.delete(ApiConfig.adminRevokeSessions(userId));
  }

  static Future<List<SessionInfo>> getAdminSessions({int limit = 100}) async {
    final response = await _dio.get(
      ApiConfig.adminSessions,
      queryParameters: {'limit': limit},
    );
    return (response.data as List).map((j) => SessionInfo.fromJson(j)).toList();
  }
}
