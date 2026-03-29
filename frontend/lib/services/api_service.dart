/// Fabio — API Service
///
/// Dio-based REST client with automatic JWT injection.

import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../models/models.dart';
import 'auth_service.dart';

class ApiService {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
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
    final token = response.data['access_token'];
    await AuthService.saveToken(token);
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

  // ── User ──────────────────────────────────────────────────────────────

  static Future<User> getMe() async {
    final response = await _dio.get(ApiConfig.userMe);
    return User.fromJson(response.data);
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
    double balance = 0.0,
  }) async {
    final response = await _dio.post(ApiConfig.accounts, data: {
      'account_number': accountNumber,
      'bank_name': bankName,
      'balance': balance.toString(),
    });
    return BankAccount.fromJson(response.data);
  }

  // ── Security Settings ─────────────────────────────────────────────────

  static Future<SecuritySettings> getSecuritySettings() async {
    final response = await _dio.get(ApiConfig.security);
    return SecuritySettings.fromJson(response.data);
  }

  static Future<SecuritySettings> updateThreshold(double amount) async {
    final response = await _dio.patch(ApiConfig.security, data: {
      'threshold_amount': amount.toString(),
    });
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
      'amount': amount.toString(),
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
}
