/// Fabio — DNS Resolver Helper
///
/// Provides a DNS-over-HTTPS (DoH) fallback when the device's local DNS
/// cannot resolve a hostname (common on Indian mobile carriers with
/// restrictive DNS).
///
/// Flow:
///   1. Try system DNS (InternetAddress.lookup)
///   2. If that fails → query Google DoH (dns.google)
///   3. If that fails → query Cloudflare DoH (1.1.1.1)
///   4. Cache successful resolutions for the session

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class DnsResolver {
  DnsResolver._();

  /// In-memory cache: hostname → resolved IP (lasts for app session)
  static final Map<String, String> _cache = {};

  /// Dedicated Dio for DoH queries — short timeout, no auth interceptors
  static final Dio _dohDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );

  /// Resolve a hostname to an IP address.
  /// Uses system DNS first, then falls back to Google/Cloudflare DoH.
  static Future<String?> resolve(String hostname) async {
    // Check cache first
    if (_cache.containsKey(hostname)) {
      debugPrint('[DNS] Cache hit: $hostname → ${_cache[hostname]}');
      return _cache[hostname];
    }

    // 1. Try system DNS
    try {
      final addresses = await InternetAddress.lookup(hostname);
      if (addresses.isNotEmpty) {
        final ip = addresses.first.address;
        _cache[hostname] = ip;
        debugPrint('[DNS] System resolved: $hostname → $ip');
        return ip;
      }
    } catch (e) {
      debugPrint('[DNS] System DNS failed for $hostname: $e');
    }

    // 2. Try Google DoH
    final googleIp = await _queryDoH(
      'https://dns.google/resolve',
      hostname,
    );
    if (googleIp != null) {
      _cache[hostname] = googleIp;
      debugPrint('[DNS] Google DoH resolved: $hostname → $googleIp');
      return googleIp;
    }

    // 3. Try Cloudflare DoH
    final cfIp = await _queryDoH(
      'https://cloudflare-dns.com/dns-query',
      hostname,
    );
    if (cfIp != null) {
      _cache[hostname] = cfIp;
      debugPrint('[DNS] Cloudflare DoH resolved: $hostname → $cfIp');
      return cfIp;
    }

    debugPrint('[DNS] All DNS methods failed for $hostname');
    return null;
  }

  /// Query a DNS-over-HTTPS endpoint (RFC 8484 JSON API)
  static Future<String?> _queryDoH(String dohUrl, String hostname) async {
    try {
      final response = await _dohDio.get(
        dohUrl,
        queryParameters: {'name': hostname, 'type': 'A'},
        options: Options(
          headers: {'Accept': 'application/dns-json'},
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final answers = data['Answer'] as List?;
        if (answers != null && answers.isNotEmpty) {
          // Find the A record (type 1)
          for (final answer in answers) {
            if (answer['type'] == 1) {
              return answer['data'] as String;
            }
          }
          // Fallback: return first answer's data
          return answers.first['data'] as String;
        }
      }
    } catch (e) {
      debugPrint('[DNS] DoH query to $dohUrl failed: $e');
    }
    return null;
  }

  /// Clear the DNS cache (useful when network changes)
  static void clearCache() {
    _cache.clear();
  }
}
