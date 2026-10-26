import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'companion_api_service.dart';

/// Information discovered about a CodeFlow Companion on the local network.
@immutable
class DiscoveredCompanion {
  final String host;
  final int port;
  final String hostname;
  final String os;
  final bool authRequired;

  const DiscoveredCompanion({
    required this.host,
    required this.port,
    required this.hostname,
    required this.os,
    required this.authRequired,
  });

  String get endpointUrl => 'http://$host:$port';
}

/// Service managing zero-setup mDNS discovery and subnet scanning.
class CompanionDiscoveryService {
  final CompanionApiService _apiService;
  bool _isSearching = false;

  CompanionDiscoveryService({CompanionApiService? apiService})
    : _apiService = apiService ?? CompanionApiService();

  bool get isSearching => _isSearching;

  /// Discover companions by querying mDNS multicast and probing local subnet
  Stream<DiscoveredCompanion> discoverCompanions({
    int targetPort = 8090,
    Duration timeout = const Duration(seconds: 4),
  }) async* {
    if (_isSearching) return;
    _isSearching = true;

    final foundHosts = <String>{};

    try {
      // 1. Probing localhost / standard host
      if (!kIsWeb) {
        final localTest = await _testHost('127.0.0.1', targetPort);
        if (localTest != null) {
          foundHosts.add('127.0.0.1');
          yield localTest;
        }

        // 2. Discover local IP subnet
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLoopback: false,
        );

        for (final interface in interfaces) {
          for (final addr in interface.addresses) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              final subnetPrefix = '${parts[0]}.${parts[1]}.${parts[2]}';
              final hostNum = int.tryParse(parts[3]) ?? 0;

              // Probe adjacent IP range around host device
              final scanRange = <int>[];
              for (int offset = -15; offset <= 15; offset++) {
                final targetNum = hostNum + offset;
                if (targetNum > 1 && targetNum < 255 && targetNum != hostNum) {
                  scanRange.add(targetNum);
                }
              }

              // Run concurrent probes in batches
              const batchSize = 10;
              for (int i = 0; i < scanRange.length; i += batchSize) {
                final end = (i + batchSize < scanRange.length)
                    ? i + batchSize
                    : scanRange.length;
                final batch = scanRange.sublist(i, end);

                final probeFutures = batch.map((hostNum) {
                  final candidateIp = '$subnetPrefix.$hostNum';
                  if (foundHosts.contains(candidateIp)) {
                    return Future.value(null);
                  }
                  return _testHost(candidateIp, targetPort);
                });

                final results = await Future.wait(probeFutures);
                for (final comp in results) {
                  if (comp != null && !foundHosts.contains(comp.host)) {
                    foundHosts.add(comp.host);
                    yield comp;
                  }
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('CompanionDiscoveryService scan error: $e');
    } finally {
      _isSearching = false;
    }
  }

  Future<DiscoveredCompanion?> _testHost(String host, int port) async {
    try {
      final isHealthy = await _apiService.checkHealth(
        host: host,
        port: port,
        timeout: const Duration(milliseconds: 300),
      );
      if (isHealthy) {
        final info = await _apiService.getInfo(
          host: host,
          port: port,
          timeout: const Duration(milliseconds: 600),
        );
        return DiscoveredCompanion(
          host: host,
          port: port,
          hostname: info?.hostname ?? host,
          os: info?.os ?? 'Desktop',
          authRequired: info?.authRequired ?? false,
        );
      }
    } catch (_) {}
    return null;
  }
}
