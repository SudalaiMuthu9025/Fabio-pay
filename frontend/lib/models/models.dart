/// Fabio — Data Models
///
/// Dart classes for API request/response mapping.

class User {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final bool isActive;
  final DateTime createdAt;

  User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isActive,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'],
        email: json['email'],
        fullName: json['full_name'],
        role: json['role'],
        isActive: json['is_active'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

class BankAccount {
  final String id;
  final String userId;
  final String accountNumber;
  final String bankName;
  final double balance;
  final String currency;
  final bool isPrimary;
  final DateTime createdAt;

  BankAccount({
    required this.id,
    required this.userId,
    required this.accountNumber,
    required this.bankName,
    required this.balance,
    required this.currency,
    required this.isPrimary,
    required this.createdAt,
  });

  factory BankAccount.fromJson(Map<String, dynamic> json) => BankAccount(
        id: json['id'],
        userId: json['user_id'],
        accountNumber: json['account_number'],
        bankName: json['bank_name'],
        balance: double.tryParse(json['balance'].toString()) ?? 0.0,
        currency: json['currency'] ?? 'INR',
        isPrimary: json['is_primary'] ?? false,
        createdAt: DateTime.parse(json['created_at']),
      );

  /// Masked display: "XXXX XXXX 1234"
  String get maskedNumber {
    if (accountNumber.length < 4) return accountNumber;
    final last4 = accountNumber.substring(accountNumber.length - 4);
    return 'XXXX XXXX $last4';
  }
}

class SecuritySettings {
  final String id;
  final String userId;
  final double thresholdAmount;
  final bool biometricEnabled;
  final int maxAttempts;
  final int failedAttempts;

  SecuritySettings({
    required this.id,
    required this.userId,
    required this.thresholdAmount,
    required this.biometricEnabled,
    required this.maxAttempts,
    required this.failedAttempts,
  });

  factory SecuritySettings.fromJson(Map<String, dynamic> json) =>
      SecuritySettings(
        id: json['id'],
        userId: json['user_id'],
        thresholdAmount:
            double.tryParse(json['threshold_amount'].toString()) ?? 10000.0,
        biometricEnabled: json['biometric_enabled'] ?? true,
        maxAttempts: json['max_attempts'] ?? 5,
        failedAttempts: json['failed_attempts'] ?? 0,
      );
}

class TransferResult {
  final String transactionId;
  final String status;
  final String authMethod;
  final String message;
  final List<String>? challengeSequence;

  TransferResult({
    required this.transactionId,
    required this.status,
    required this.authMethod,
    required this.message,
    this.challengeSequence,
  });

  factory TransferResult.fromJson(Map<String, dynamic> json) => TransferResult(
        transactionId: json['transaction_id'],
        status: json['status'],
        authMethod: json['auth_method'],
        message: json['message'],
        challengeSequence: json['challenge_sequence'] != null
            ? List<String>.from(json['challenge_sequence'])
            : null,
      );

  bool get requiresBiometric => authMethod == 'biometric';
}

class TransactionLog {
  final String id;
  final String userId;
  final double amount;
  final String currency;
  final String? description;
  final String authMethod;
  final String status;
  final String? toAccountIdentifier;
  final DateTime createdAt;

  TransactionLog({
    required this.id,
    required this.userId,
    required this.amount,
    required this.currency,
    this.description,
    required this.authMethod,
    required this.status,
    this.toAccountIdentifier,
    required this.createdAt,
  });

  factory TransactionLog.fromJson(Map<String, dynamic> json) =>
      TransactionLog(
        id: json['id'],
        userId: json['user_id'],
        amount: double.tryParse(json['amount'].toString()) ?? 0.0,
        currency: json['currency'] ?? 'INR',
        description: json['description'],
        authMethod: json['auth_method'],
        status: json['status'],
        toAccountIdentifier: json['to_account_identifier'],
        createdAt: DateTime.parse(json['created_at']),
      );
}
