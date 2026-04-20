/// Fabio — API Configuration
///
/// Centralized endpoint definitions for the Fabio backend.

class ApiConfig {
  ApiConfig._();

  /// REST API base URL
  static const String baseUrl = 'https://fabio-production-5484.up.railway.app';

  /// API Endpoints
  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String me = '/auth/me';
  static const String setPin = '/auth/set-pin';

  static const String faceRegister = '/face/register';
  static const String faceVerify = '/face/verify';

  static const String bankRegister = '/bank/register';
  static const String bankAccount = '/bank/account';

  static const String transactionsSend = '/transactions/send';
  static const String transactionsHistory = '/transactions/history';
}
