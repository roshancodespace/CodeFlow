import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/companion_info.dart';

/// Service interfacing with CodeFlow Companion HTTP endpoints.
class CompanionApiService {
  final http.Client _client;

  CompanionApiService({http.Client? client})
    : _client = client ?? http.Client();

  Map<String, String> _buildHeaders(String? token) {
    final headers = <String, String>{'Accept': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
      headers['X-CodeFlow-Token'] = token;
    }
    return headers;
  }

  /// Heartbeat check
  Future<bool> checkHealth({
    required String host,
    required int port,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      final uri = Uri.parse('http://$host:$port/health');
      final resp = await _client.get(uri).timeout(timeout);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return data['status'] == 'ok';
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Measure round-trip ping latency in milliseconds
  Future<int?> measurePingLatency({
    required String host,
    required int port,
  }) async {
    try {
      final sw = Stopwatch()..start();
      final uri = Uri.parse('http://$host:$port/health');
      final resp = await _client.get(uri).timeout(const Duration(seconds: 2));
      sw.stop();
      if (resp.statusCode == 200) {
        return sw.elapsedMilliseconds;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetch detailed host and stream information
  Future<CompanionInfo?> getInfo({
    required String host,
    required int port,
    String? token,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final uri = Uri.parse('http://$host:$port/info');
      final resp = await _client
          .get(uri, headers: _buildHeaders(token))
          .timeout(timeout);
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        return CompanionInfo.fromJson(json);
      }
      return null;
    } catch (e) {
      debugPrint('CompanionApiService getInfo error: $e');
      return null;
    }
  }

  /// Fetch a single screenshot frame as JPEG bytes
  Future<Uint8List?> getScreenshot({
    required String host,
    required int port,
    String? token,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final uri = Uri.parse('http://$host:$port/screenshot');
      final headers = _buildHeaders(token)..['Accept'] = 'image/jpeg';
      final resp = await _client.get(uri, headers: headers).timeout(timeout);
      if (resp.statusCode == 200) {
        return resp.bodyBytes;
      }
      return null;
    } catch (e) {
      debugPrint('CompanionApiService getScreenshot error: $e');
      return null;
    }
  }

  /// Perform OCR analysis on the current screen frame
  Future<OcrResult?> getScreenOcr({
    required String host,
    required int port,
    String? token,
    String? query,
    String region = 'top',
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final qParams = <String, String>{
        if (query != null && query.isNotEmpty) 'query': query,
        'region': region,
      };
      final uri = Uri.http('$host:$port', '/ocr', qParams);
      final resp = await _client
          .get(uri, headers: _buildHeaders(token))
          .timeout(timeout);
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        return OcrResult.fromJson(json);
      }
      return null;
    } catch (e) {
      debugPrint('CompanionApiService getScreenOcr error: $e');
      return null;
    }
  }

  /// Query the currently active window title
  Future<String?> getActiveWindow({
    required String host,
    required int port,
    String? token,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      final uri = Uri.parse('http://$host:$port/window/active');
      final resp = await _client
          .get(uri, headers: _buildHeaders(token))
          .timeout(timeout);
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        return json['active_window'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('CompanionApiService getActiveWindow error: $e');
      return null;
    }
  }

  /// Update the authorized workspace directory on the host companion
  Future<bool> setWorkspaceDirectory({
    required String host,
    required int port,
    required String path,
    String? token,
  }) async {
    try {
      final uri = Uri.parse('http://$host:$port/workspace/set');
      final headers = _buildHeaders(token)
        ..['Content-Type'] = 'application/json';
      final resp = await _client
          .post(uri, headers: headers, body: jsonEncode({'path': path}))
          .timeout(const Duration(seconds: 3));
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('CompanionApiService setWorkspaceDirectory error: $e');
      return false;
    }
  }

  void dispose() {
    _client.close();
  }
}
