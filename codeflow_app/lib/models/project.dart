import 'package:flutter/foundation.dart';
import 'source_file.dart';

/// Represents a locally stored project workspace in CodeFlow.
@immutable
class Project {
  final String id;
  final String name;
  final String rootPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int totalFiles;
  final int totalSizeInBytes;
  final List<SourceFile> files;

  const Project({
    required this.id,
    required this.name,
    required this.rootPath,
    required this.createdAt,
    required this.updatedAt,
    this.totalFiles = 0,
    this.totalSizeInBytes = 0,
    this.files = const [],
  });

  int get selectedFilesCount =>
      files.where((f) => !f.isDirectory && f.isSelected).length;

  int get selectedCodeFilesCount =>
      files.where((f) => f.isCodeFile && f.isSelected).length;

  Project copyWith({
    String? id,
    String? name,
    String? rootPath,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? totalFiles,
    int? totalSizeInBytes,
    List<SourceFile>? files,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      rootPath: rootPath ?? this.rootPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      totalFiles: totalFiles ?? this.totalFiles,
      totalSizeInBytes: totalSizeInBytes ?? this.totalSizeInBytes,
      files: files ?? this.files,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rootPath': rootPath,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'totalFiles': totalFiles,
        'totalSizeInBytes': totalSizeInBytes,
        'files': files.map((f) => f.toJson()).toList(),
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        name: json['name'] as String,
        rootPath: json['rootPath'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        totalFiles: json['totalFiles'] as int? ?? 0,
        totalSizeInBytes: json['totalSizeInBytes'] as int? ?? 0,
        files: (json['files'] as List<dynamic>?)
                ?.map((f) => SourceFile.fromJson(f as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}
