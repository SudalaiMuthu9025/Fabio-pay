/// Fabio — Data Models
///
/// Dart classes for API request/response mapping.

class User {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final bool isActive;
  final String? googleId;
  final String? avatarUrl;
  final bool isFaceRegistered;
  final DateTime createdAt;

  User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isActive,
    this.googleId,
    this.avatarUrl,
    this.isFaceRegistered = false,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'],
        email: json['email'],
        fullName: json['full_name'],
        role: json['role'],
        isActive: json['is_active'],
        googleId: json['google_id'],
        avatarUrl: json['avatar_url'],
        isFaceRegistered: json['is_face_registered'] ?? false,
        createdAt: DateTime.parse(json['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'full_name': fullName,
        'role': role,
        'is_active': isActive,
        'google_id': googleId,
        'avatar_url': avatarUrl,
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
  final String bankName;
  final String? ifscCode;
  final double balance;
  final String currency;
  final bool isPrimary;
  final bool isVerified;
  final DateTime createdAt;

  BankAccount({
    required this.id,
    required this.userId,
    required this.accountNumber,
    required this.bankName,
    this.ifscCode,
    required this.balance,
    required this.currency,
    required this.isPrimary,
    this.isVerified = false,
    required this.createdAt,
  });

  factory BankAccount.fromJson(Map<String, dynamic> json) => BankAccount(
        id: json['id'],
        userId: json['user_id'],
        accountNumber: json['account_number'],
        bankName: json['bank_name'],
        ifscCode: json['ifsc_code'],
        balance: double.tryParse(json['balance'].toString()) ?? 0.0,
        currency: json['currency'] ?? 'INR',
        isPrimary: json['is_primary'] ?? false,
        isVerified: json['is_verified'] ?? false,
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
  final int lockoutDurationMinutes;
  final String? lockedUntil;

  SecuritySettings({
    required this.id,
    required this.userId,
    required this.thresholdAmount,
    required this.biometricEnabled,
    required this.maxAttempts,
    required this.failedAttempts,
    required this.lockoutDurationMinutes,
    this.lockedUntil,
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
        lockoutDurationMinutes: json['lockout_duration_minutes'] ?? 30,
        lockedUntil: json['locked_until'],
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
  final String? fromAccountId;
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
    this.fromAccountId,
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
        fromAccountId: json['from_account_id'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

class SessionInfo {
  final String id;
  final String userId;
  final String? ipAddress;
  final String? userAgent;
  final bool isActive;
  final DateTime createdAt;
  final DateTime expiresAt;

  SessionInfo({
    required this.id,
    required this.userId,
    this.ipAddress,
    this.userAgent,
    required this.isActive,
    required this.createdAt,
    required this.expiresAt,
  });

  factory SessionInfo.fromJson(Map<String, dynamic> json) => SessionInfo(
        id: json['id'],
        userId: json['user_id'],
        ipAddress: json['ip_address'],
        userAgent: json['user_agent'],
        isActive: json['is_active'] ?? true,
        createdAt: DateTime.parse(json['created_at']),
        expiresAt: DateTime.parse(json['expires_at']),
      );
}

class AdminDashboardStats {
  final int totalUsers;
  final int activeUsers;
  final int totalTransactions;
  final int successfulTransactions;
  final int failedTransactions;
  final int pendingTransactions;
  final int activeSessions;
  final double totalVolume;
  final int faceRegisteredUsers;

  AdminDashboardStats({
    required this.totalUsers,
    required this.activeUsers,
    required this.totalTransactions,
    required this.successfulTransactions,
    required this.failedTransactions,
    required this.pendingTransactions,
    required this.activeSessions,
    required this.totalVolume,
    required this.faceRegisteredUsers,
  });

  factory AdminDashboardStats.fromJson(Map<String, dynamic> json) =>
      AdminDashboardStats(
        totalUsers: json['total_users'] ?? 0,
        activeUsers: json['active_users'] ?? 0,
        totalTransactions: json['total_transactions'] ?? 0,
        successfulTransactions: json['successful_transactions'] ?? 0,
        failedTransactions: json['failed_transactions'] ?? 0,
        pendingTransactions: json['pending_transactions'] ?? 0,
        activeSessions: json['active_sessions'] ?? 0,
        totalVolume: double.tryParse(json['total_volume'].toString()) ?? 0.0,
        faceRegisteredUsers: json['face_registered_users'] ?? 0,
      );
}
