/// Fabio — API Configuration
///
/// Centralized endpoint definitions for the Fabio backend.

class ApiConfig {
  ApiConfig._();

  /// REST API base URL
  static const String baseUrl = 'https://fabio-pay-production.up.railway.app';

  /// API Endpoints — Auth
  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String me = '/auth/me';
  static const String setPin = '/auth/set-pin';
  static const String verifyPin = '/auth/verify-pin';

  /// API Endpoints — Face
  static const String faceRegister = '/face/register';
  static const String faceVerify = '/face/verify';

  /// API Endpoints — Bank
  static const String bankRegister = '/bank/register';
  static const String bankAccount = '/bank/account';

  /// API Endpoints — Transactions
  static const String transactionsSend = '/transactions/send';
  static const String transactionsDeposit = '/transactions/deposit';
  static const String transactionsHistory = '/transactions/history';
  static String transactionDetail(String id) => '/transactions/$id';

  /// API Endpoints — Beneficiary
  static const String beneficiaryAdd = '/beneficiary/add';
  static const String beneficiaryList = '/beneficiary/list';
  static String beneficiaryDelete(String id) => '/beneficiary/$id';
  static String beneficiaryFavorite(String id) => '/beneficiary/$id/favorite';

  /// API Endpoints — Profile
  static const String profileUpdate = '/profile/update';
  static const String changePassword = '/profile/change-password';
  static const String changePin = '/profile/change-pin';
  static const String loginHistory = '/profile/login-history';
  static const String reRegisterFace = '/profile/re-register-face';
  static const String profileLimits = '/profile/limits';
  static const String profileUpdateLimits = '/profile/update-limits';

  /// API Endpoints — Analytics
  static const String spendingSummary = '/analytics/spending-summary';

  /// API Endpoints — QR
  static const String qrMyCode = '/qr/my-code';
  static const String qrDecode = '/qr/decode';

  /// API Endpoints — Payment Requests
  static const String requestCreate = '/requests/create';
  static const String requestIncoming = '/requests/incoming';
  static const String requestOutgoing = '/requests/outgoing';
  static String requestPay(String id) => '/requests/$id/pay';
  static String requestDecline(String id) => '/requests/$id/decline';

  /// API Endpoints — Admin
  static const String adminUsers = '/admin/users';
  static String adminUserRole(String id) => '/admin/users/$id/role';
  static String adminUserStatus(String id) => '/admin/users/$id/status';

  /// Health
  static const String health = '/api/health';
}
