/// Fabio — API Service
///
/// Dio-based REST client with JWT Bearer token auto-injection.

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

  static Future<User> register({
    required String email,
    required String fullName,
    required String phone,
    required String password,
  }) async {
    final response = await _dio.post(ApiConfig.register, data: {
      'email': email,
      'full_name': fullName,
      'phone': phone,
      'password': password,
    });
    return User.fromJson(response.data);
  }

  static Future<String> login(String email, String password) async {
    final response = await _dio.post(ApiConfig.login, data: {
      'email': email,
      'password': password,
    });
    final token = response.data['access_token'];
    await AuthService.saveToken(token);
    // Fetch and cache user profile
    final user = await getMe();
    await AuthService.saveUserJson(jsonEncode(user.toJson()));
    return token;
  }

  static Future<User> getMe() async {
    final response = await _dio.get(ApiConfig.me);
    return User.fromJson(response.data);
  }

  static Future<User> setPin(String pin) async {
    final response = await _dio.post(ApiConfig.setPin, data: {
      'pin': pin,
    });
    return User.fromJson(response.data);
  }

  static Future<void> logout() async {
    await AuthService.clearAll();
  }

  // ── Face ──────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> registerFace(String base64Image) async {
    final response = await _dio.post(ApiConfig.faceRegister, data: {
      'image': base64Image,
    });
    return response.data;
  }

  static Future<Map<String, dynamic>> verifyFace(String base64Image) async {
    final response = await _dio.post(ApiConfig.faceVerify, data: {
      'image': base64Image,
    });
    return response.data;
  }

  // ── Bank ──────────────────────────────────────────────────────────────

  static Future<BankAccount> registerBank({
    required String accountNumber,
    required String ifscCode,
    required String accountHolderName,
  }) async {
    final response = await _dio.post(ApiConfig.bankRegister, data: {
      'account_number': accountNumber,
      'ifsc_code': ifscCode,
      'account_holder_name': accountHolderName,
    });
    return BankAccount.fromJson(response.data);
  }

  static Future<List<BankAccount>> getAccounts() async {
    final response = await _dio.get(ApiConfig.bankAccount);
    return (response.data as List)
        .map((j) => BankAccount.fromJson(j))
        .toList();
  }

  // ── Transactions ──────────────────────────────────────────────────────

  static Future<SendMoneyResult> sendMoney({
    required String toAccount,
    required double amount,
    required String pin,
    String? description,
    bool faceVerified = false,
  }) async {
    final response = await _dio.post(ApiConfig.transactionsSend, data: {
      'to_account_identifier': toAccount,
      'amount': amount,
      'pin': pin,
      'description': description,
      'face_verified': faceVerified,
    });
    return SendMoneyResult.fromJson(response.data);
  }

  static Future<List<TransactionModel>> getTransactionHistory() async {
    final response = await _dio.get(ApiConfig.transactionsHistory);
    return (response.data as List)
        .map((j) => TransactionModel.fromJson(j))
        .toList();
  }
}
