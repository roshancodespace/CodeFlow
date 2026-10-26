import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/project.dart';
import '../models/source_file.dart';
import '../core/storage/local_storage_service.dart';

/// Service handling ZIP imports, GitHub repo imports, and project workspace file trees.
class ProjectManagerService {
  final LocalStorageService _storage;
  final http.Client _client;

  ProjectManagerService({
    required LocalStorageService storage,
    http.Client? client,
  })  : _storage = storage,
        _client = client ?? http.Client();

  /// Get the base directory where projects are stored on device
  Future<Directory> _getWorkspacesDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final workspaces = Directory(p.join(appDir.path, 'codeflow_workspaces'));
    if (!await workspaces.exists()) {
      await workspaces.create(recursive: true);
    }
    return workspaces;
  }

  /// Safe extraction of ZIP bytes preventing directory traversal attacks
  Future<Project> importFromZipBytes({
    required List<int> zipBytes,
    required String projectName,
  }) async {
    final sanitizedName = projectName.replaceAll(RegExp(r'[^\w\s\.-]'), '_').trim();
    final projectId = 'proj_${DateTime.now().millisecondsSinceEpoch}';
    final workspacesDir = await _getWorkspacesDir();
    final projectDir = Directory(p.join(workspacesDir.path, projectId));

    if (await projectDir.exists()) {
      await projectDir.delete(recursive: true);
    }
    await projectDir.create(recursive: true);

    final archive = ZipDecoder().decodeBytes(zipBytes);
    final sourceFiles = <SourceFile>[];
    int totalBytes = 0;

    for (final file in archive) {
      final rawPath = file.name;
      // Path traversal security check
      final normPath = p.normalize(rawPath).replaceAll('\\', '/');
      if (normPath.startsWith('..') || normPath.contains('/../') || p.isAbsolute(normPath)) {
        debugPrint('Skipping unsafe ZIP entry: $rawPath');
        continue;
      }

      final outPath = p.join(projectDir.path, normPath);
      // Ensure target path stays strictly inside projectDir
      if (!p.isWithin(projectDir.path, outPath) && outPath != projectDir.path) {
        debugPrint('Target path escapes project directory: $normPath');
        continue;
      }

      if (file.isFile) {
        final contentBytes = file.content as List<int>;
        totalBytes += contentBytes.length;
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(contentBytes);

        String? contentStr;
        try {
          contentStr = utf8.decode(contentBytes);
        } catch (_) {
          contentStr = null; // Binary file
        }

        final sha = sha256.convert(contentBytes).toString();
        final ext = p.extension(normPath);

        sourceFiles.add(SourceFile(
          path: outPath,
          relativePath: normPath,
          sizeInBytes: contentBytes.length,
          extension: ext,
          isDirectory: false,
          isSelected: true,
          content: contentStr,
          sha256: sha,
        ));
      } else {
        await Directory(outPath).create(recursive: true);
        sourceFiles.add(SourceFile(
          path: outPath,
          relativePath: normPath,
          sizeInBytes: 0,
          extension: '',
          isDirectory: true,
          isSelected: true,
        ));
      }
    }

    // Sort files alphabetically with directories first
    sourceFiles.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.relativePath.compareTo(b.relativePath);
    });

    final project = Project(
      id: projectId,
      name: sanitizedName.isNotEmpty ? sanitizedName : 'Imported Project',
      rootPath: projectDir.path,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      totalFiles: sourceFiles.where((f) => !f.isDirectory).length,
      totalSizeInBytes: totalBytes,
      files: sourceFiles,
    );

    await _storage.saveProject(project);
    return project;
  }

  /// Import a public GitHub repository without requiring git CLI
  Future<Project> importFromGitHub({
    required String repoUrlOrSlug,
    void Function(String message)? onProgress,
  }) async {
    // Parse owner and repo from "owner/repo" or "https://github.com/owner/repo"
    String slug = repoUrlOrSlug.trim();
    if (slug.startsWith('https://github.com/')) {
      slug = slug.substring('https://github.com/'.length);
    } else if (slug.startsWith('http://github.com/')) {
      slug = slug.substring('http://github.com/'.length);
    } else if (slug.startsWith('github.com/')) {
      slug = slug.substring('github.com/'.length);
    }
    slug = slug.replaceAll(RegExp(r'\.git$'), '').trim().replaceAll(RegExp(r'/+$'), '');

    final parts = slug.split('/');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      throw Exception('Invalid GitHub repository format. Use "owner/repo" or full URL.');
    }

    final owner = parts[0];
    final repo = parts[1];
    onProgress?.call('Fetching repository archive for $owner/$repo...');

    // Try main branch archive first, fallback to master
    final downloadUrls = [
      'https://github.com/$owner/$repo/archive/refs/heads/main.zip',
      'https://github.com/$owner/$repo/archive/refs/heads/master.zip',
      'https://api.github.com/repos/$owner/$repo/zipball/HEAD',
    ];

    List<int>? zipBytes;
    for (final url in downloadUrls) {
      try {
        final resp = await _client.get(
          Uri.parse(url),
          headers: {'User-Agent': 'CodeFlow-Mobile-App'},
        ).timeout(const Duration(seconds: 40));

        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          zipBytes = resp.bodyBytes;
          break;
        }
      } catch (_) {}
    }

    if (zipBytes == null) {
      throw Exception(
        'Failed to download GitHub repository $owner/$repo. Please verify the repository is public and accessible.',
      );
    }

    onProgress?.call('Extracting files and indexing project structure...');
    return importFromZipBytes(
      zipBytes: zipBytes,
      projectName: repo,
    );
  }

  /// Create a sample starter project with typical source files for instant testing
  Future<Project> createSampleProject() async {
    final sampleFiles = <Map<String, String>>[
      {
        'path': 'lib/main.dart',
        'content': "void main() {\n  print('Hello from CodeFlow!');\n}\n",
      },
      {
        'path': 'lib/models/user.dart',
        'content': "class User {\n  final String id;\n  final String name;\n  User(this.id, this.name);\n}\n",
      },
      {
        'path': 'scripts/deploy.py',
        'content': "import sys\nprint('Running CodeFlow deployment script...')\n",
      },
      {
        'path': 'README.md',
        'content': "# CodeFlow Workspace\nAutomated cross-platform coding and terminal injection.\n",
      },
      {
        'path': 'config/settings.json',
        'content': '{\n  "version": "1.0.0",\n  "debug": true\n}\n',
      },
    ];

    final archive = Archive();
    for (final sf in sampleFiles) {
      final bytes = utf8.encode(sf['content']!);
      archive.addFile(ArchiveFile(sf['path']!, bytes.length, bytes));
    }

    final encoder = ZipEncoder();
    final zipBytes = encoder.encode(archive);
    return importFromZipBytes(
      zipBytes: zipBytes!,
      projectName: 'CodeFlow Sample Project',
    );
  }

  void dispose() {
    _client.close();
  }
}
