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

  static Future<Map<String, dynamic>> reRegisterFace(String base64Image) async {
    final response = await _dio.post(ApiConfig.reRegisterFace, data: {
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
    String paymentMode = 'ACCOUNT',
    bool faceVerified = false,
  }) async {
    final response = await _dio.post(ApiConfig.transactionsSend, data: {
      'to_account_identifier': toAccount,
      'amount': amount,
      'pin': pin,
      'description': description,
      'payment_mode': paymentMode,
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

  static Future<Map<String, dynamic>> deposit({
    required double amount,
    required String pin,
  }) async {
    final response = await _dio.post(ApiConfig.transactionsDeposit, data: {
      'amount': amount,
      'pin': pin,
    });
    return response.data;
  }

  // ── Beneficiaries ─────────────────────────────────────────────────────

  static Future<Beneficiary> addBeneficiary({
    required String name,
    required String accountNumber,
    String? ifscCode,
    String? nickname,
  }) async {
    final response = await _dio.post(ApiConfig.beneficiaryAdd, data: {
      'name': name,
      'account_number': accountNumber,
      if (ifscCode != null) 'ifsc_code': ifscCode,
      if (nickname != null) 'nickname': nickname,
    });
    return Beneficiary.fromJson(response.data);
  }

  static Future<List<Beneficiary>> getBeneficiaries() async {
    final response = await _dio.get(ApiConfig.beneficiaryList);
    return (response.data as List)
        .map((j) => Beneficiary.fromJson(j))
        .toList();
  }

  static Future<void> deleteBeneficiary(String id) async {
    await _dio.delete(ApiConfig.beneficiaryDelete(id));
  }

  static Future<Beneficiary> toggleFavorite(String id) async {
    final response = await _dio.patch(ApiConfig.beneficiaryFavorite(id));
    return Beneficiary.fromJson(response.data);
  }

  // ── Profile ───────────────────────────────────────────────────────────

  static Future<User> updateProfile({String? fullName, String? phone}) async {
    final data = <String, dynamic>{};
    if (fullName != null) data['full_name'] = fullName;
    if (phone != null) data['phone'] = phone;
    final response = await _dio.patch(ApiConfig.profileUpdate, data: data);
    return User.fromJson(response.data);
  }

  static Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _dio.post(ApiConfig.changePassword, data: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
    return response.data;
  }

  static Future<bool> verifyPin(String pin) async {
    try {
      final response = await _dio.post(ApiConfig.verifyPin, data: {
        'pin': pin,
      });
      return response.data['valid'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    final response = await _dio.post(ApiConfig.changePin, data: {
      'current_pin': currentPin,
      'new_pin': newPin,
    });
    return response.data;
  }

  static Future<List<LoginLog>> getLoginHistory() async {
    final response = await _dio.get(ApiConfig.loginHistory);
    return (response.data as List)
        .map((j) => LoginLog.fromJson(j))
        .toList();
  }

  // ── Admin ─────────────────────────────────────────────────────────────

  static Future<List<User>> getAdminUsers() async {
    final response = await _dio.get(ApiConfig.adminUsers);
    return (response.data as List)
        .map((j) => User.fromJson(j))
        .toList();
  }

  static Future<User> changeUserRole(String userId, String role) async {
    final response = await _dio.patch(
      ApiConfig.adminUserRole(userId),
      data: {'role': role},
    );
    return User.fromJson(response.data);
  }

  static Future<User> toggleUserStatus(String userId, bool isActive) async {
    final response = await _dio.patch(
      ApiConfig.adminUserStatus(userId),
      data: {'is_active': isActive},
    );
    return User.fromJson(response.data);
  }

  // ── Transaction Detail (Receipt) ──────────────────────────────────────

  static Future<TransactionModel> getTransactionDetail(String id) async {
    final response = await _dio.get(ApiConfig.transactionDetail(id));
    return TransactionModel.fromJson(response.data);
  }

  // ── Spending Analytics ────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getSpendingSummary() async {
    final response = await _dio.get(ApiConfig.spendingSummary);
    return response.data;
  }

  // ── QR Code ───────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getMyQrCode() async {
    final response = await _dio.get(ApiConfig.qrMyCode);
    return response.data;
  }

  static Future<Map<String, dynamic>> decodeQr(String payload) async {
    final response = await _dio.post(ApiConfig.qrDecode, data: {
      'payload': payload,
    });
    return response.data;
  }

  // ── Payment Requests ──────────────────────────────────────────────────

  static Future<Map<String, dynamic>> createPaymentRequest({
    required String toAccountIdentifier,
    required double amount,
    String? description,
  }) async {
    final response = await _dio.post(ApiConfig.requestCreate, data: {
      'to_account_identifier': toAccountIdentifier,
      'amount': amount,
      if (description != null) 'description': description,
    });
    return response.data;
  }

  static Future<List<Map<String, dynamic>>> getIncomingRequests() async {
    final response = await _dio.get(ApiConfig.requestIncoming);
    return (response.data as List).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> getOutgoingRequests() async {
    final response = await _dio.get(ApiConfig.requestOutgoing);
    return (response.data as List).cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> payRequest(String id, String pin) async {
    final response = await _dio.post(ApiConfig.requestPay(id), data: {
      'pin': pin,
    });
    return response.data;
  }

  static Future<Map<String, dynamic>> declineRequest(String id) async {
    final response = await _dio.post(ApiConfig.requestDecline(id));
    return response.data;
  }

  // ── Transaction Limits ────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getTransactionLimits() async {
    final response = await _dio.get(ApiConfig.profileLimits);
    return response.data;
  }

  static Future<Map<String, dynamic>> updateTransactionLimits({
    double? dailyLimit,
    double? monthlyLimit,
  }) async {
    final data = <String, dynamic>{};
    if (dailyLimit != null) data['daily_transfer_limit'] = dailyLimit;
    if (monthlyLimit != null) data['monthly_transfer_limit'] = monthlyLimit;
    final response = await _dio.post(ApiConfig.profileUpdateLimits, data: data);
    return response.data;
  }
}
