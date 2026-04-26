/// Fabio — Data Models
///
/// Dart classes for API request/response mapping.

class User {
  final String id;
  final String email;
  final String fullName;
  final String? phone;
  final String role;
  final bool isActive;
  final bool isFaceRegistered;
  final bool hasPin;
  final bool hasBankAccount;
  final bool? biometricLoginEnabled;
  final DateTime createdAt;

  User({
    required this.id,
    required this.email,
    required this.fullName,
    this.phone,
    required this.role,
    required this.isActive,
    this.isFaceRegistered = false,
    this.hasPin = false,
    this.hasBankAccount = false,
    this.biometricLoginEnabled,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'],
        email: json['email'],
        fullName: json['full_name'],
        phone: json['phone'],
        role: json['role'],
        isActive: json['is_active'],
        isFaceRegistered: json['is_face_registered'] ?? false,
        hasPin: json['has_pin'] ?? false,
        hasBankAccount: json['has_bank_account'] ?? false,
        biometricLoginEnabled: json['biometric_login_enabled'],
        createdAt: DateTime.parse(json['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'full_name': fullName,
        'phone': phone,
        'role': role,
        'is_active': isActive,
        'is_face_registered': isFaceRegistered,
        'has_pin': hasPin,
        'has_bank_account': hasBankAccount,
        'biometric_login_enabled': biometricLoginEnabled,
        'created_at': createdAt.toIso8601String(),
      };

  String get initials {
    final parts = fullName.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
  }
}

class BankAccount {
  final String id;
  final String userId;
  final String accountNumber;
  final String ifscCode;
  final String accountHolderName;
  final double balance;
  final String currency;
  final bool isPrimary;
  final DateTime createdAt;

  BankAccount({
    required this.id,
    required this.userId,
    required this.accountNumber,
    required this.ifscCode,
    required this.accountHolderName,
    required this.balance,
    required this.currency,
    required this.isPrimary,
    required this.createdAt,
  });

  factory BankAccount.fromJson(Map<String, dynamic> json) => BankAccount(
        id: json['id'],
        userId: json['user_id'],
        accountNumber: json['account_number'],
        ifscCode: json['ifsc_code'],
        accountHolderName: json['account_holder_name'],
        balance: double.tryParse(json['balance'].toString()) ?? 0.0,
        currency: json['currency'],
        isPrimary: json['is_primary'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

class TransactionModel {
  final String id;
  final String userId;
  final String? counterpartUserId;
  final String transactionType; // DEBIT or CREDIT
  final String? fromAccountId;
  final String toAccountIdentifier;
  final double amount;
  final String currency;
  final String? description;
  final String paymentMode;
  final String authMethod;
  final String status;
  final DateTime createdAt;
  // Enriched receipt fields
  final String? senderName;
  final String? receiverName;
  final String? senderAccount;
  final String? receiverAccount;

  TransactionModel({
    required this.id,
    required this.userId,
    this.counterpartUserId,
    this.transactionType = 'DEBIT',
    this.fromAccountId,
    required this.toAccountIdentifier,
    required this.amount,
    required this.currency,
    this.description,
    this.paymentMode = 'ACCOUNT',
    required this.authMethod,
    required this.status,
    required this.createdAt,
    this.senderName,
    this.receiverName,
    this.senderAccount,
    this.receiverAccount,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) =>
      TransactionModel(
        id: json['id'],
        userId: json['user_id'],
        counterpartUserId: json['counterpart_user_id'],
        transactionType: json['transaction_type'] ?? 'DEBIT',
        fromAccountId: json['from_account_id'],
        toAccountIdentifier: json['to_account_identifier'],
        amount: double.tryParse(json['amount'].toString()) ?? 0.0,
        currency: json['currency'],
        description: json['description'],
        paymentMode: json['payment_mode'] ?? 'ACCOUNT',
        authMethod: json['auth_method'],
        status: json['status'],
        createdAt: DateTime.parse(json['created_at']),
        senderName: json['sender_name'],
        receiverName: json['receiver_name'],
        senderAccount: json['sender_account'],
        receiverAccount: json['receiver_account'],
      );

  bool get isCredit => transactionType == 'CREDIT';
  bool get isDebit => transactionType == 'DEBIT';

  String get modeIcon {
    switch (paymentMode) {
      case 'UPI': return '⚡';
      case 'QR': return '📱';
      default: return '🏦';
    }
  }

  String get directionLabel => isCredit ? 'Received' : 'Sent';
}

class SendMoneyResult {
  final String transactionId;
  final String status;
  final String authMethod;
  final String message;
  final bool requiresLiveness;

  SendMoneyResult({
    required this.transactionId,
    required this.status,
    required this.authMethod,
    required this.message,
    required this.requiresLiveness,
  });

  factory SendMoneyResult.fromJson(Map<String, dynamic> json) =>
      SendMoneyResult(
        transactionId: json['transaction_id'],
        status: json['status'],
        authMethod: json['auth_method'],
        message: json['message'],
        requiresLiveness: json['requires_liveness'] ?? false,
      );
}

class Beneficiary {
  final String id;
  final String userId;
  final String name;
  final String accountNumber;
  final String? ifscCode;
  final String? nickname;
  final bool isFavorite;
  final DateTime createdAt;

  Beneficiary({
    required this.id,
    required this.userId,
    required this.name,
    required this.accountNumber,
    this.ifscCode,
    this.nickname,
    required this.isFavorite,
    required this.createdAt,
  });

  factory Beneficiary.fromJson(Map<String, dynamic> json) => Beneficiary(
        id: json['id'],
        userId: json['user_id'],
        name: json['name'],
        accountNumber: json['account_number'],
        ifscCode: json['ifsc_code'],
        nickname: json['nickname'],
        isFavorite: json['is_favorite'] ?? false,
        createdAt: DateTime.parse(json['created_at']),
      );

  String get displayName => nickname ?? name;
}

class LoginLog {
  final String id;
  final String? ipAddress;
  final String? userAgent;
  final bool success;
  final DateTime createdAt;

  LoginLog({
    required this.id,
    this.ipAddress,
    this.userAgent,
    required this.success,
    required this.createdAt,
  });

  factory LoginLog.fromJson(Map<String, dynamic> json) => LoginLog(
        id: json['id'],
        ipAddress: json['ip_address'],
        userAgent: json['user_agent'],
        success: json['success'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

class PaymentRequest {
  final String id;
  final String requesterId;
  final String payerAccountIdentifier;
  final double amount;
  final String? description;
  final String status;
  final String? requesterName;
  final DateTime createdAt;

  PaymentRequest({
    required this.id,
    required this.requesterId,
    required this.payerAccountIdentifier,
    required this.amount,
    this.description,
    required this.status,
    this.requesterName,
    required this.createdAt,
  });

  factory PaymentRequest.fromJson(Map<String, dynamic> json) =>
      PaymentRequest(
        id: json['id'],
        requesterId: json['requester_id'],
        payerAccountIdentifier: json['payer_account_identifier'],
        amount: double.tryParse(json['amount'].toString()) ?? 0.0,
        description: json['description'],
        status: json['status'],
        requesterName: json['requester_name'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

