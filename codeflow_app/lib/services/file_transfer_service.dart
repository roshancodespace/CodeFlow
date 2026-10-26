import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/source_file.dart';

/// Result of an individual file transfer operation.
@immutable
class FileTransferResult {
  final String relativePath;
  final bool success;
  final int bytesWritten;
  final String sha256;
  final String? errorMessage;

  const FileTransferResult({
    required this.relativePath,
    required this.success,
    this.bytesWritten = 0,
    required this.sha256,
    this.errorMessage,
  });
}

/// Service managing direct network file transfers to the host PC companion.
class FileTransferService {
  final http.Client _client;

  FileTransferService({http.Client? client}) : _client = client ?? http.Client();

  /// Calculate SHA-256 hash of UTF-8 content
  static String computeSha256(String content) {
    final bytes = utf8.encode(content);
    return sha256.convert(bytes).toString();
  }

  /// Transfer an individual source file to the companion workspace
  Future<FileTransferResult> transferFile({
    required String host,
    required int port,
    String? token,
    required SourceFile file,
    required String fileContent,
    bool overwrite = true,
  }) async {
    final hash = computeSha256(fileContent);

    try {
      final uri = Uri.parse('http://$host:$port/workspace/transfer');
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
        headers['X-CodeFlow-Token'] = token;
      }

      final payload = jsonEncode({
        'relative_path': file.relativePath,
        'content': fileContent,
        'encoding': 'utf-8',
        'sha256': hash,
        'overwrite': overwrite,
      });

      final resp = await _client
          .post(uri, headers: headers, body: payload)
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return FileTransferResult(
          relativePath: file.relativePath,
          success: data['verified'] as bool? ?? true,
          bytesWritten: data['bytes_written'] as int? ?? 0,
          sha256: hash,
        );
      } else {
        String msg = 'HTTP ${resp.statusCode}';
        try {
          final errJson = jsonDecode(resp.body) as Map<String, dynamic>;
          msg = errJson['error'] as String? ?? msg;
        } catch (_) {}
        return FileTransferResult(
          relativePath: file.relativePath,
          success: false,
          sha256: hash,
          errorMessage: msg,
        );
      }
    } catch (e) {
      return FileTransferResult(
        relativePath: file.relativePath,
        success: false,
        sha256: hash,
        errorMessage: e.toString(),
      );
    }
  }

  void dispose() {
    _client.close();
  }
}
