import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:codeflow_app/models/companion_info.dart';
import 'package:codeflow_app/models/source_file.dart';
import 'package:codeflow_app/services/companion_api_service.dart';

void main() {
  group('OcrResult Model Tests', () {
    test('parses JSON payload accurately', () {
      final json = {
        'success': true,
        'has_tesseract': true,
        'active_window': 'Bawaal - Antigravity IDE - pubspec.yaml',
        'is_vscode': true,
        'query': 'pubspec.yaml',
        'query_found': true,
        'is_terminal_open': true,
        'text': 'File Edit Selection ... pubspec.yaml ...',
        'elapsed_ms': 742.5,
      };

      final ocr = OcrResult.fromJson(json);
      expect(ocr.success, isTrue);
      expect(ocr.hasTesseract, isTrue);
      expect(ocr.activeWindow, equals('Bawaal - Antigravity IDE - pubspec.yaml'));
      expect(ocr.isVscode, isTrue);
      expect(ocr.query, equals('pubspec.yaml'));
      expect(ocr.queryFound, isTrue);
      expect(ocr.isTerminalOpen, isTrue);
      expect(ocr.elapsedMs, equals(742.5));
    });

    test('handles empty or missing JSON fields with safe defaults', () {
      final ocr = OcrResult.fromJson(const {});
      expect(ocr.success, isFalse);
      expect(ocr.hasTesseract, isFalse);
      expect(ocr.activeWindow, isEmpty);
      expect(ocr.isVscode, isFalse);
      expect(ocr.queryFound, isFalse);
      expect(ocr.isTerminalOpen, isFalse);
      expect(ocr.elapsedMs, equals(0.0));
    });
  });

  group('SourceFile Name Getter Tests', () {
    test('extracts basename from nested paths and root files', () {
      const nested = SourceFile(
        path: '/workspace/lib/features/auth/login_screen.dart',
        relativePath: 'lib/features/auth/login_screen.dart',
        sizeInBytes: 1024,
        extension: '.dart',
      );
      expect(nested.name, equals('login_screen.dart'));

      const root = SourceFile(
        path: '/workspace/pubspec.yaml',
        relativePath: 'pubspec.yaml',
        sizeInBytes: 512,
        extension: '.yaml',
      );
      expect(root.name, equals('pubspec.yaml'));
    });
  });

  group('CompanionApiService OCR & Window Endpoints', () {
    test('getScreenOcr returns parsed OcrResult when HTTP 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/ocr'));
        expect(request.url.queryParameters['query'], equals('main.dart'));
        expect(request.url.queryParameters['region'], equals('top'));
        return http.Response(
          jsonEncode({
            'success': true,
            'has_tesseract': true,
            'active_window': 'CodeFlow - Visual Studio Code',
            'is_vscode': true,
            'query': 'main.dart',
            'query_found': true,
            'text': 'main.dart tab buffer',
            'elapsed_ms': 650.0,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = CompanionApiService(client: mockClient);
      final res = await service.getScreenOcr(
        host: '127.0.0.1',
        port: 8090,
        query: 'main.dart',
      );

      expect(res, isNotNull);
      expect(res!.queryFound, isTrue);
      expect(res.isVscode, isTrue);
      expect(res.activeWindow, contains('Visual Studio Code'));
    });

    test('getActiveWindow returns window title string', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/window/active'));
        return http.Response(
          jsonEncode({
            'success': true,
            'active_window': 'CodeFlow - Visual Studio Code',
            'is_vscode': true,
          }),
          200,
        );
      });

      final service = CompanionApiService(client: mockClient);
      final title = await service.getActiveWindow(host: '127.0.0.1', port: 8090);
      expect(title, equals('CodeFlow - Visual Studio Code'));
    });

    test('setWorkspaceDirectory posts valid directory path', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/workspace/set'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['path'], equals('/new/workspace'));
        return http.Response(
          jsonEncode({'status': 'success', 'workspace_dir': '/new/workspace'}),
          200,
        );
      });

      final service = CompanionApiService(client: mockClient);
      final ok = await service.setWorkspaceDirectory(
        host: '127.0.0.1',
        port: 8090,
        path: '/new/workspace',
      );
      expect(ok, isTrue);
    });
  });
}
