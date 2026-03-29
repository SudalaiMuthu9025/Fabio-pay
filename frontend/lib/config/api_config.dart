/// Fabio — API Configuration
///
/// Base URLs for REST and WebSocket connections.
/// Change these when deploying to production.

class ApiConfig {
  ApiConfig._();

  /// REST API base URL
  static const String baseUrl = 'http://10.0.2.2:8000'; // Android emulator → localhost
  // static const String baseUrl = 'http://localhost:8000'; // iOS simulator
  // static const String baseUrl = 'https://api.fabiopay.com'; // Production

  /// WebSocket URL for liveness verification
  static const String wsUrl = 'ws://10.0.2.2:8000/ws/liveness';
  // static const String wsUrl = 'wss://api.fabiopay.com/ws/liveness'; // Production

  /// API paths
  static const String login = '/api/auth/login';
  static const String register = '/api/auth/register';
  static const String userMe = '/api/users/me';
  static const String accounts = '/api/accounts/';
  static const String security = '/api/security/';
  static const String transfer = '/api/transactions/transfer';
  static const String transactions = '/api/transactions/';
  static const String health = '/api/health';
}
