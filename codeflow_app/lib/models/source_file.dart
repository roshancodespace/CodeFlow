import 'package:flutter/foundation.dart';

/// Represents a source code file within a project.
@immutable
class SourceFile {
  final String path;
  final String relativePath;
  final int sizeInBytes;
  final String extension;
  final bool isDirectory;
  final bool isSelected;
  final String? content;
  final String? sha256;

  const SourceFile({
    required this.path,
    required this.relativePath,
    required this.sizeInBytes,
    required this.extension,
    this.isDirectory = false,
    this.isSelected = true,
    this.content,
    this.sha256,
  });

  bool get isCodeFile {
    if (isDirectory) return false;
    const codeExtensions = {
      '.dart',
      '.kt',
      '.java',
      '.py',
      '.js',
      '.ts',
      '.tsx',
      '.jsx',
      '.c',
      '.cpp',
      '.h',
      '.hpp',
      '.cs',
      '.go',
      '.rs',
      '.swift',
      '.rb',
      '.php',
      '.html',
      '.css',
      '.json',
      '.yaml',
      '.yml',
      '.xml',
      '.sh',
      '.bash',
      '.sql',
      '.md',
    };
    return codeExtensions.contains(extension.toLowerCase());
  }

  SourceFile copyWith({
    String? path,
    String? relativePath,
    int? sizeInBytes,
    String? extension,
    bool? isDirectory,
    bool? isSelected,
    String? content,
    String? sha256,
  }) {
    return SourceFile(
      path: path ?? this.path,
      relativePath: relativePath ?? this.relativePath,
      sizeInBytes: sizeInBytes ?? this.sizeInBytes,
      extension: extension ?? this.extension,
      isDirectory: isDirectory ?? this.isDirectory,
      isSelected: isSelected ?? this.isSelected,
      content: content ?? this.content,
      sha256: sha256 ?? this.sha256,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'relativePath': relativePath,
        'sizeInBytes': sizeInBytes,
        'extension': extension,
        'isDirectory': isDirectory,
        'isSelected': isSelected,
        'sha256': sha256,
      };

  factory SourceFile.fromJson(Map<String, dynamic> json) => SourceFile(
        path: json['path'] as String,
        relativePath: json['relativePath'] as String,
        sizeInBytes: json['sizeInBytes'] as int? ?? 0,
        extension: json['extension'] as String? ?? '',
        isDirectory: json['isDirectory'] as bool? ?? false,
        isSelected: json['isSelected'] as bool? ?? true,
        sha256: json['sha256'] as String?,
      );
}
