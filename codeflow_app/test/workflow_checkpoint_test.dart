import 'package:flutter_test/flutter_test.dart';
import 'package:codeflow_app/models/workflow_checkpoint.dart';

void main() {
  group('WorkflowCheckpoint Tests', () {
    test('serializes and deserializes correctly', () {
      final now = DateTime.now();
      final original = WorkflowCheckpoint(
        projectId: 'test_proj_123',
        workflowVersion: 1,
        currentOperationIndex: 2,
        currentFileIndex: 3,
        charOffset: 120,
        status: WorkflowExecutionStatus.paused,
        completedRelativePaths: const ['lib/a.dart', 'lib/b.dart'],
        lastUpdated: now,
      );

      final json = original.toJson();
      final restored = WorkflowCheckpoint.fromJson(json);

      expect(restored.projectId, equals(original.projectId));
      expect(restored.currentFileIndex, equals(3));
      expect(restored.charOffset, equals(120));
      expect(restored.status, equals(WorkflowExecutionStatus.paused));
      expect(restored.canResume, isTrue);
      expect(restored.completedRelativePaths, contains('lib/a.dart'));
    });

    test('canResume returns true for paused or failed states', () {
      final paused = WorkflowCheckpoint(
        projectId: 'p1',
        status: WorkflowExecutionStatus.paused,
        lastUpdated: DateTime.now(),
      );
      expect(paused.canResume, isTrue);

      final idle = WorkflowCheckpoint(
        projectId: 'p2',
        status: WorkflowExecutionStatus.idle,
        lastUpdated: DateTime.now(),
      );
      expect(idle.canResume, isFalse);

      final completed = WorkflowCheckpoint(
        projectId: 'p3',
        status: WorkflowExecutionStatus.completed,
        lastUpdated: DateTime.now(),
      );
      expect(completed.canResume, isFalse);
    });
  });
}
