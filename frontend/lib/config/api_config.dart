/// Fabio — API Configuration
///
/// Base URLs for REST and WebSocket connections.
/// Change `baseUrl` when deploying to production.

class ApiConfig {
  ApiConfig._();

  /// REST API base URL
  /// For physical device on same WiFi, use your machine's WiFi IP.
  /// After deployment, use your Railway/production URL.
  static const String baseUrl = 'http://10.0.2.2:8000'; // Android emulator
  // static const String baseUrl = 'http://192.168.1.100:8000'; // Physical device (change IP)
  // static const String baseUrl = 'https://your-app.railway.app'; // Production

  /// WebSocket URL for liveness verification
  static String wsUrl(String token) => baseUrl.replaceFirst('http', 'ws') + '/ws/liveness?token=$token';

  /// API Endpoints
  static const String login = '/api/auth/login';
  static const String register = '/api/auth/register';
  static const String registerFace = '/api/security/register-face';
  static const String logout = '/api/auth/logout';
  static const String sessions = '/api/auth/sessions';
  static const String googleAuth = '/api/auth/google';
  static const String userMe = '/api/users/me';
  static const String accounts = '/api/accounts/';
  static const String security = '/api/security/';
  static const String transfer = '/api/transactions/transfer';
  static const String transactions = '/api/transactions/';
  static const String health = '/api/health';

  // Admin API Endpoints
  static const String adminDashboard = '/api/admin/dashboard';
  static const String adminUsers = '/api/admin/users';
  static const String adminSessions = '/api/admin/sessions';
  static const String adminAuditLogs = '/api/admin/audit-logs';
  static String adminChangeRole(String userId) => '/api/admin/users/$userId/role';
  static String adminChangeStatus(String userId) => '/api/admin/users/$userId/status';
  static String adminVerifyBank(String bankId) => '/api/admin/verify-bank/$bankId';
  static String adminRevokeSessions(String userId) => '/api/admin/revoke-sessions/$userId';
}
