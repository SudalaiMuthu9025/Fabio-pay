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
  final String? fromAccountId;
  final String toAccountIdentifier;
  final double amount;
  final String currency;
  final String? description;
  final String authMethod;
  final String status;
  final DateTime createdAt;

  TransactionModel({
    required this.id,
    required this.userId,
    this.fromAccountId,
    required this.toAccountIdentifier,
    required this.amount,
    required this.currency,
    this.description,
    required this.authMethod,
    required this.status,
    required this.createdAt,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) =>
      TransactionModel(
        id: json['id'],
        userId: json['user_id'],
        fromAccountId: json['from_account_id'],
        toAccountIdentifier: json['to_account_identifier'],
        amount: double.tryParse(json['amount'].toString()) ?? 0.0,
        currency: json['currency'],
        description: json['description'],
        authMethod: json['auth_method'],
        status: json['status'],
        createdAt: DateTime.parse(json['created_at']),
      );
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
