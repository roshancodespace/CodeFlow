import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../models/workflow_checkpoint.dart';
import '../../workflows/orchestrator_controller.dart';

class AutomationScreen extends ConsumerStatefulWidget {
  const AutomationScreen({super.key});

  @override
  ConsumerState<AutomationScreen> createState() => _AutomationScreenState();
}

class _AutomationScreenState extends ConsumerState<AutomationScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final selectedProject = ref.read(selectedProjectProvider);
      if (selectedProject != null) {
        ref
            .read(orchestratorProvider)
            .checkResumableCheckpoint(selectedProject.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark
        ? AppColors.darkSurface
        : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    final storage = ref.watch(localStorageProvider);
    final selectedProject = ref.watch(selectedProjectProvider);
    final orchestrator = ref.watch(orchestratorProvider);
    final orchState = orchestrator.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Automation Orchestrator'),
        actions: [
          // Emergency Panic Button
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton.icon(
              icon: const Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: AppColors.statusError,
              ),
              label: const Text(
                'PANIC',
                style: TextStyle(
                  color: AppColors.statusError,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: () async {
                await orchestrator.emergencyPanicRelease();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Emergency release report sent: All keys released.',
                      ),
                      backgroundColor: AppColors.statusError,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: selectedProject == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.folder_off_outlined,
                        size: 40,
                        color: AppColors.lightTextMuted,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No project selected for automation.',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Select a project from the Projects tab to begin.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.lightTextMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                children: [
                  // Active Project Banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      border: Border.all(color: borderColor),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.folder,
                          color: AppColors.accentLight,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedProject.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${selectedProject.selectedFilesCount} files selected (${selectedProject.selectedCodeFilesCount} code)',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.lightTextMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Resumable Checkpoint Alert if available
                  if (orchState.canResume)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.statusWarning.withAlpha(25),
                        border: Border.all(
                          color: AppColors.statusWarning.withAlpha(100),
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.history,
                                color: AppColors.statusWarning,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Resumable Checkpoint Detected',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.statusWarning,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Previous automation was interrupted. You can resume from the last saved file or start fresh.',
                            style: TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              FilledButton(
                                onPressed: () {
                                  orchestrator.runWorkflow(
                                    project: selectedProject,
                                    resumeFromCheckpoint: true,
                                  );
                                },
                                child: const Text('Resume from Checkpoint'),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: () {
                                  orchestrator.runWorkflow(
                                    project: selectedProject,
                                    resumeFromCheckpoint: false,
                                  );
                                },
                                child: const Text('Start Fresh'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  // Execution Status & Progress Box
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      border: Border.all(color: borderColor),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Status: ${_statusName(orchState.status)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            if (orchState.status ==
                                WorkflowExecutionStatus.inProgress)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          orchState.currentOperation,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.lightTextSecondary,
                          ),
                        ),
                        if (orchState.totalFiles > 0) ...[
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                            value: orchState.totalFiles > 0
                                ? (orchState.currentFileIndex /
                                          orchState.totalFiles)
                                      .clamp(0.0, 1.0)
                                : 0.0,
                            backgroundColor: borderColor,
                            valueColor: const AlwaysStoppedAnimation(
                              AppColors.accentLight,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'File ${orchState.currentFileIndex} of ${orchState.totalFiles}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.lightTextMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Execution Controls
                  Row(
                    children: [
                      if (orchState.status !=
                          WorkflowExecutionStatus.inProgress)
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: const Text('Start Workflow'),
                            onPressed: () {
                              orchestrator.runWorkflow(
                                project: selectedProject,
                                resumeFromCheckpoint: false,
                              );
                            },
                          ),
                        )
                      else ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.pause, size: 18),
                            label: const Text('Pause'),
                            onPressed: orchestrator.pause,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(
                              Icons.stop,
                              size: 18,
                              color: AppColors.statusError,
                            ),
                            label: const Text(
                              'Cancel',
                              style: TextStyle(color: AppColors.statusError),
                            ),
                            onPressed: orchestrator.cancel,
                          ),
                        ),
                      ],
                      if (orchState.status ==
                          WorkflowExecutionStatus.paused) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: const Text('Resume'),
                            onPressed: orchestrator.resume,
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Workflow Steps Preview
                  const Text(
                    'Workflow Sequence',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),

                  ..._buildStepList(orchState, surfaceColor, borderColor),

                  const SizedBox(height: 20),

                  // Cadence & Simulation Settings
                  const Text(
                    'Cadence & Typing Simulation',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),

                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      border: Border.all(color: borderColor),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Target CPS Slider (Humanized Speed: 2 - 30 CPS)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Human Typing Speed',
                              style: TextStyle(fontSize: 12),
                            ),
                            Text(
                              '${storage.typingSpeedCps} CPS (~${(storage.typingSpeedCps * 12).round()} WPM)',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: storage.typingSpeedCps.toDouble().clamp(
                            2.0,
                            30.0,
                          ),
                          min: 2,
                          max: 30,
                          divisions: 28,
                          onChanged: (val) {
                            storage.setTypingSpeedCps(val.round());
                            setState(() {});
                          },
                        ),

                        // Human Mistakes & Auto-corrections
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Human Mistakes & Auto-Corrections',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: const Text(
                            'Randomized typos on adjacent keys with realistic backspace fixes',
                            style: TextStyle(fontSize: 10),
                          ),
                          value: storage.humanMistakesEnabled,
                          onChanged: (val) {
                            storage.setHumanMistakesEnabled(val);
                            setState(() {});
                          },
                        ),

                        if (storage.humanMistakesEnabled) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Typo Mistake Frequency',
                                style: TextStyle(fontSize: 11),
                              ),
                              Text(
                                '${storage.mistakeProbabilityPercent}% of keys',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: storage.mistakeProbabilityPercent
                                .toDouble()
                                .clamp(1.0, 10.0),
                            min: 1,
                            max: 10,
                            divisions: 9,
                            onChanged: (val) {
                              storage.setMistakeProbabilityPercent(val.round());
                              setState(() {});
                            },
                          ),
                        ],

                        // Syntax & Thinking Pauses Switch
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Developer Syntax & Thought Pauses',
                            style: TextStyle(fontSize: 12),
                          ),
                          subtitle: const Text(
                            'Pauses at newlines, semicolons, brackets, and reading intervals',
                            style: TextStyle(fontSize: 10),
                          ),
                          value: storage.thinkingPausesEnabled,
                          onChanged: (val) {
                            storage.setThinkingPausesEnabled(val);
                            setState(() {});
                          },
                        ),

                        // Focus Delay Slider
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Focus Window Delay',
                              style: TextStyle(fontSize: 12),
                            ),
                            Text(
                              '${storage.focusDelaySeconds}s',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: storage.focusDelaySeconds.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          onChanged: (val) {
                            storage.setFocusDelaySeconds(val.round());
                            setState(() {});
                          },
                        ),

                        // Newline Pause Slider
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Newline Pause (Formatter catch-up)',
                              style: TextStyle(fontSize: 12),
                            ),
                            Text(
                              '${storage.newlinePauseMs}ms',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: storage.newlinePauseMs.toDouble().clamp(
                            50.0,
                            800.0,
                          ),
                          min: 50,
                          max: 800,
                          divisions: 15,
                          onChanged: (val) {
                            storage.setNewlinePauseMs(val.round());
                            setState(() {});
                          },
                        ),

                        // Human Jitter Switch
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Human Jitter (Gaussian micro-variance)',
                            style: TextStyle(fontSize: 12),
                          ),
                          subtitle: const Text(
                            'Box-Muller variation on every keystroke interval',
                            style: TextStyle(fontSize: 10),
                          ),
                          value: storage.humanJitterEnabled,
                          onChanged: (val) {
                            storage.setHumanJitterEnabled(val);
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  List<Widget> _buildStepList(
    OrchestratorState state,
    Color surface,
    Color border,
  ) {
    if (state.steps.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: surface,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'Workflow will automatically initialize upon start.',
            style: TextStyle(fontSize: 12, color: AppColors.lightTextMuted),
          ),
        ),
      ];
    }

    return state.steps.asMap().entries.map((entry) {
      final idx = entry.key;
      final step = entry.value;

      Widget icon;
      if (step.isCompleted) {
        icon = const Icon(
          Icons.check_circle,
          size: 16,
          color: AppColors.statusSuccess,
        );
      } else if (step.isInProgress) {
        icon = const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      } else if (step.hasFailed) {
        icon = const Icon(Icons.cancel, size: 16, color: AppColors.statusError);
      } else {
        icon = const Icon(
          Icons.radio_button_unchecked,
          size: 16,
          color: AppColors.lightTextMuted,
        );
      }

      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: surface,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${idx + 1}. ${step.title}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    step.details,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.lightTextMuted,
                    ),
                  ),
                  if (step.error != null)
                    Text(
                      step.error!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.statusError,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  String _statusName(WorkflowExecutionStatus status) {
    switch (status) {
      case WorkflowExecutionStatus.inProgress:
        return 'Running';
      case WorkflowExecutionStatus.paused:
        return 'Paused';
      case WorkflowExecutionStatus.completed:
        return 'Completed';
      case WorkflowExecutionStatus.failed:
        return 'Failed';
      case WorkflowExecutionStatus.cancelled:
        return 'Cancelled';
      case WorkflowExecutionStatus.idle:
        return 'Ready';
    }
  }
}
