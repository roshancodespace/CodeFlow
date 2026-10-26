import 'package:flutter/foundation.dart';

enum WorkflowExecutionStatus {
  idle,
  inProgress,
  paused,
  completed,
  failed,
  cancelled,
}

/// Checkpoint Memory model for resuming interrupted workflows.
@immutable
class WorkflowCheckpoint {
  final String projectId;
  final int workflowVersion;
  final int currentOperationIndex;
  final int currentFileIndex;
  final int charOffset;
  final WorkflowExecutionStatus status;
  final List<String> completedRelativePaths;
  final DateTime lastUpdated;
  final String? lastError;

  const WorkflowCheckpoint({
    required this.projectId,
    this.workflowVersion = 1,
    this.currentOperationIndex = 0,
    this.currentFileIndex = 0,
    this.charOffset = 0,
    this.status = WorkflowExecutionStatus.idle,
    this.completedRelativePaths = const [],
    required this.lastUpdated,
    this.lastError,
  });

  bool get canResume =>
      status == WorkflowExecutionStatus.paused ||
      status == WorkflowExecutionStatus.failed ||
      (status == WorkflowExecutionStatus.inProgress &&
          (currentFileIndex > 0 || charOffset > 0));

  WorkflowCheckpoint copyWith({
    String? projectId,
    int? workflowVersion,
    int? currentOperationIndex,
    int? currentFileIndex,
    int? charOffset,
    WorkflowExecutionStatus? status,
    List<String>? completedRelativePaths,
    DateTime? lastUpdated,
    String? lastError,
  }) {
    return WorkflowCheckpoint(
      projectId: projectId ?? this.projectId,
      workflowVersion: workflowVersion ?? this.workflowVersion,
      currentOperationIndex:
          currentOperationIndex ?? this.currentOperationIndex,
      currentFileIndex: currentFileIndex ?? this.currentFileIndex,
      charOffset: charOffset ?? this.charOffset,
      status: status ?? this.status,
      completedRelativePaths:
          completedRelativePaths ?? this.completedRelativePaths,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() => {
    'projectId': projectId,
    'workflowVersion': workflowVersion,
    'currentOperationIndex': currentOperationIndex,
    'currentFileIndex': currentFileIndex,
    'charOffset': charOffset,
    'status': status.name,
    'completedRelativePaths': completedRelativePaths,
    'lastUpdated': lastUpdated.toIso8601String(),
    'lastError': lastError,
  };

  factory WorkflowCheckpoint.fromJson(Map<String, dynamic> json) =>
      WorkflowCheckpoint(
        projectId: json['projectId'] as String,
        workflowVersion: json['workflowVersion'] as int? ?? 1,
        currentOperationIndex: json['currentOperationIndex'] as int? ?? 0,
        currentFileIndex: json['currentFileIndex'] as int? ?? 0,
        charOffset: json['charOffset'] as int? ?? 0,
        status: WorkflowExecutionStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => WorkflowExecutionStatus.idle,
        ),
        completedRelativePaths:
            (json['completedRelativePaths'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        lastUpdated: DateTime.parse(json['lastUpdated'] as String),
        lastError: json['lastError'] as String?,
      );
}
