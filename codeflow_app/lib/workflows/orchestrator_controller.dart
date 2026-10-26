import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/project.dart';
import '../models/workflow_checkpoint.dart';
import '../services/bluetooth_hid_service.dart';
import '../services/companion_api_service.dart';
import '../services/file_transfer_service.dart';
import '../services/typing_cadence_engine.dart';
import '../core/storage/local_storage_service.dart';

/// Workflow Step Description
@immutable
class WorkflowStep {
  final String title;
  final String details;
  final bool isCompleted;
  final bool isInProgress;
  final bool hasFailed;
  final String? error;

  const WorkflowStep({
    required this.title,
    required this.details,
    this.isCompleted = false,
    this.isInProgress = false,
    this.hasFailed = false,
    this.error,
  });

  WorkflowStep copyWith({
    String? title,
    String? details,
    bool? isCompleted,
    bool? isInProgress,
    bool? hasFailed,
    String? error,
  }) {
    return WorkflowStep(
      title: title ?? this.title,
      details: details ?? this.details,
      isCompleted: isCompleted ?? this.isCompleted,
      isInProgress: isInProgress ?? this.isInProgress,
      hasFailed: hasFailed ?? this.hasFailed,
      error: error ?? this.error,
    );
  }
}

/// Orchestrator Status State
@immutable
class OrchestratorState {
  final WorkflowExecutionStatus status;
  final List<WorkflowStep> steps;
  final int currentStepIndex;
  final int currentFileIndex;
  final int totalFiles;
  final int currentCharacterOffset;
  final int focusCountdownRemaining;
  final String currentOperation;
  final String? errorMessage;
  final bool canResume;

  const OrchestratorState({
    this.status = WorkflowExecutionStatus.idle,
    this.steps = const [],
    this.currentStepIndex = 0,
    this.currentFileIndex = 0,
    this.totalFiles = 0,
    this.currentCharacterOffset = 0,
    this.focusCountdownRemaining = 0,
    this.currentOperation = 'Ready',
    this.errorMessage,
    this.canResume = false,
  });

  OrchestratorState copyWith({
    WorkflowExecutionStatus? status,
    List<WorkflowStep>? steps,
    int? currentStepIndex,
    int? currentFileIndex,
    int? totalFiles,
    int? currentCharacterOffset,
    int? focusCountdownRemaining,
    String? currentOperation,
    String? errorMessage,
    bool? canResume,
  }) {
    return OrchestratorState(
      status: status ?? this.status,
      steps: steps ?? this.steps,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      currentFileIndex: currentFileIndex ?? this.currentFileIndex,
      totalFiles: totalFiles ?? this.totalFiles,
      currentCharacterOffset:
          currentCharacterOffset ?? this.currentCharacterOffset,
      focusCountdownRemaining:
          focusCountdownRemaining ?? this.focusCountdownRemaining,
      currentOperation: currentOperation ?? this.currentOperation,
      errorMessage: errorMessage ?? this.errorMessage,
      canResume: canResume ?? this.canResume,
    );
  }
}

/// High-level orchestrator coordinating PC terminal automation,
/// Bluetooth HID keyboard input, direct file transfers, and checkpoint persistence.
class OrchestratorController extends ChangeNotifier {
  final IBluetoothHidService _hidService;
  final CompanionApiService _companionApi;
  final FileTransferService _fileTransferService;
  final TypingCadenceEngine _cadenceEngine;
  final LocalStorageService _storage;

  OrchestratorState _state = const OrchestratorState();
  StreamSubscription? _typingSubscription;
  bool _isCancelled = false;

  OrchestratorController({
    required IBluetoothHidService hidService,
    required CompanionApiService companionApi,
    required FileTransferService fileTransferService,
    required TypingCadenceEngine cadenceEngine,
    required LocalStorageService storage,
  })  : _hidService = hidService,
        _companionApi = companionApi,
        _fileTransferService = fileTransferService,
        _cadenceEngine = cadenceEngine,
        _storage = storage {
    _initTypingListener();
  }

  OrchestratorState get state => _state;

  void _initTypingListener() {
    _typingSubscription = _cadenceEngine.progressStream.listen((prog) {
      _state = _state.copyWith(
        currentFileIndex: prog.fileIndex,
        currentCharacterOffset: prog.charOffset,
        currentOperation: 'Typing: ${prog.currentFileName} (${(prog.progressPercent * 100).toInt()}%)',
      );
      notifyListeners();
    });
  }

  /// Check if a resumable checkpoint exists for the project
  WorkflowCheckpoint? checkResumableCheckpoint(String projectId) {
    final cp = _storage.getCheckpoint(projectId);
    final canResume = cp != null && cp.canResume;
    _state = _state.copyWith(canResume: canResume);
    notifyListeners();
    return cp;
  }

  /// Build planned workflow steps based on selected files and available connectivity
  List<WorkflowStep> planWorkflow({
    required Project project,
    required bool companionAvailable,
    required String targetOs,
  }) {
    final selectedFiles = project.files.where((f) => !f.isDirectory && f.isSelected).toList();
    final isMac = targetOs.toLowerCase().contains('darwin') || targetOs.toLowerCase().contains('mac');
    final useDirect = _storage.automationMode == 'directNetwork' && companionAvailable;

    final steps = <WorkflowStep>[
      WorkflowStep(
        title: 'Validation',
        details: 'Verify ${selectedFiles.length} selected files and project integrity',
      ),
      WorkflowStep(
        title: 'Focus Window Delay',
        details: 'Countdown ${_storage.focusDelaySeconds}s to focus VS Code or Terminal on PC',
      ),
      WorkflowStep(
        title: 'Toggle Terminal',
        details: isMac
            ? 'Shortcut: Cmd + ` (VS Code Terminal)'
            : 'Shortcut: Ctrl + ` (VS Code Terminal)',
      ),
      WorkflowStep(
        title: useDirect ? 'Direct Network Transfer' : 'Humanized HID Keystroke Typing',
        details: useDirect
            ? 'Fast direct transfer of ${selectedFiles.length} files to PC workspace'
            : 'Typing ${selectedFiles.length} files via Bluetooth HID keyboard at ${_storage.typingSpeedCps} CPS with human jitter',
      ),
      WorkflowStep(
        title: 'Save & Post-Run Execution',
        details: _storage.postRunCommand.isNotEmpty
            ? 'Save editor (Ctrl+S) and execute: "${_storage.postRunCommand}"'
            : 'Verify completion and trigger save shortcut (Ctrl/Cmd + S)',
      ),
    ];

    return steps;
  }

  /// Start or resume workflow
  Future<void> runWorkflow({
    required Project project,
    bool resumeFromCheckpoint = false,
  }) async {
    _isCancelled = false;
    final selectedFiles = project.files.where((f) => !f.isDirectory && f.isSelected).toList();
    if (selectedFiles.isEmpty) {
      _state = _state.copyWith(
        status: WorkflowExecutionStatus.failed,
        errorMessage: 'No files selected for workflow.',
      );
      notifyListeners();
      return;
    }

    // 1. Check companion connectivity
    final host = _storage.companionHost;
    final port = _storage.companionPort;
    final token = _storage.companionToken;
    final companionInfo = await _companionApi.getInfo(host: host, port: port, token: token);
    final companionAvailable = companionInfo != null;
    final targetOs = companionInfo?.os ?? (defaultTargetPlatform == TargetPlatform.macOS ? 'Darwin' : 'Linux');

    // 2. Load or initialize checkpoint
    int startFileIndex = 0;
    int startCharOffset = 0;
    List<String> completedFiles = [];

    if (resumeFromCheckpoint) {
      final cp = _storage.getCheckpoint(project.id);
      if (cp != null && cp.canResume) {
        startFileIndex = cp.currentFileIndex.clamp(0, selectedFiles.length - 1);
        startCharOffset = cp.charOffset;
        completedFiles = List.from(cp.completedRelativePaths);
      }
    }

    final steps = planWorkflow(
      project: project,
      companionAvailable: companionAvailable,
      targetOs: targetOs,
    );

    _state = _state.copyWith(
      status: WorkflowExecutionStatus.inProgress,
      steps: steps,
      currentStepIndex: 0,
      currentFileIndex: startFileIndex,
      totalFiles: selectedFiles.length,
      currentCharacterOffset: startCharOffset,
      currentOperation: 'Validating project workspace...',
      errorMessage: null,
      canResume: false,
    );
    notifyListeners();

    try {
      // Step 0: Validation
      await _executeStep(0, () async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      if (_isCancelled) return;

      // Step 1: Focus Window Countdown
      await _executeStep(1, () async {
        _cadenceEngine.config = _cadenceEngine.config.copyWith(
          focusDelaySeconds: _storage.focusDelaySeconds,
          targetCps: _storage.typingSpeedCps,
          newlinePauseMs: _storage.newlinePauseMs,
          humanJitterEnabled: _storage.humanJitterEnabled,
        );

        await _cadenceEngine.executeFocusDelay(onTick: (sec) {
          _state = _state.copyWith(
            focusCountdownRemaining: sec,
            currentOperation: sec > 0 ? 'Focus target PC window ($sec s)...' : 'Starting automation...',
          );
          notifyListeners();
        });
      });
      if (_isCancelled) return;

      // Step 2: Open Terminal / VS Code
      await _executeStep(2, () async {
        final isMac = targetOs.toLowerCase().contains('darwin') || targetOs.toLowerCase().contains('mac');
        // Press Ctrl + ~ (or Cmd + ~ on Mac)
        await _hidService.sendKeyChord(
          hidCode: HidScancodes.graveAccentTilde,
          ctrl: !isMac,
          meta: isMac,
        );
        await Future.delayed(const Duration(milliseconds: 400));
      });
      if (_isCancelled) return;

      // Step 3: File Transfer or Typing
      await _executeStep(3, () async {
        for (int i = startFileIndex; i < selectedFiles.length; i++) {
          if (_isCancelled) break;
          final file = selectedFiles[i];
          _state = _state.copyWith(
            currentFileIndex: i,
            currentOperation: 'Processing ${file.relativePath}...',
          );
          notifyListeners();

          final content = file.content ?? '';

          final useDirect = _storage.automationMode == 'directNetwork' && companionAvailable;

          if (useDirect) {
            // Direct network transfer to workspace
            final result = await _fileTransferService.transferFile(
              host: host,
              port: port,
              token: token,
              file: file,
              fileContent: content,
            );
            if (!result.success) {
              throw Exception('Direct transfer failed for ${file.relativePath}: ${result.errorMessage}');
            }
          } else {
            // Real Human Bluetooth HID Keystroke Typing via terminal
            final isWindows = targetOs.toLowerCase().contains('windows');
            final dir = file.relativePath.contains('/')
                ? file.relativePath.substring(0, file.relativePath.lastIndexOf('/'))
                : '';

            // 1. Prepare directory in terminal if nested
            if (dir.isNotEmpty && startCharOffset == 0) {
              final mkdirCmd = isWindows ? 'mkdir -Force "$dir"\n' : 'mkdir -p "$dir"\n';
              for (final ch in mkdirCmd.split('')) {
                await _hidService.typeCharacter(ch);
                await Future.delayed(const Duration(milliseconds: 15));
              }
              await Future.delayed(const Duration(milliseconds: 200));
            }

            // 2. Prepare file injection command in shell
            if (startCharOffset == 0) {
              final headerCmd = isWindows
                  ? 'powershell -Command "Set-Content -Path \'${file.relativePath}\' -Value @\'\n'
                  : 'cat << \'CODEFLOW_EOF\' > "${file.relativePath}"\n';
              for (final ch in headerCmd.split('')) {
                await _hidService.typeCharacter(ch);
                await Future.delayed(const Duration(milliseconds: 14));
              }
              await Future.delayed(const Duration(milliseconds: 150));
            }

            // 3. Humanized cadence typing of file contents
            final charsTyped = await _cadenceEngine.typeContent(
              content: content,
              fileName: file.relativePath,
              fileIndex: i,
              totalFiles: selectedFiles.length,
              startOffset: (i == startFileIndex) ? startCharOffset : 0,
            );

            // 4. Close heredoc in terminal
            if (!_isCancelled) {
              final footerCmd = isWindows ? '\n\'@"\n' : '\nCODEFLOW_EOF\n';
              for (final ch in footerCmd.split('')) {
                await _hidService.typeCharacter(ch);
                await Future.delayed(const Duration(milliseconds: 14));
              }
              await Future.delayed(const Duration(milliseconds: 300));
            }

            if (_isCancelled) {
              await _storage.saveCheckpoint(WorkflowCheckpoint(
                projectId: project.id,
                currentFileIndex: i,
                charOffset: charsTyped,
                status: WorkflowExecutionStatus.paused,
                completedRelativePaths: completedFiles,
                lastUpdated: DateTime.now(),
              ));
              return;
            }
          }

          completedFiles.add(file.relativePath);
          // Persist progress checkpoint
          await _storage.saveCheckpoint(WorkflowCheckpoint(
            projectId: project.id,
            currentFileIndex: i + 1,
            charOffset: 0,
            status: WorkflowExecutionStatus.inProgress,
            completedRelativePaths: completedFiles,
            lastUpdated: DateTime.now(),
          ));
        }
      });
      if (_isCancelled) return;

      // Step 4: Verification, Save & Post-Run Command
      await _executeStep(4, () async {
        final isMac = targetOs.toLowerCase().contains('darwin') || targetOs.toLowerCase().contains('mac');
        // Trigger Ctrl + S to save active editor
        await _hidService.sendKeyChord(
          hidCode: HidScancodes.keyS,
          ctrl: !isMac,
          meta: isMac,
        );
        await Future.delayed(const Duration(milliseconds: 350));

        // If post-run command is configured, type and execute it in terminal
        final postCmd = _storage.postRunCommand;
        if (postCmd.isNotEmpty) {
          _state = _state.copyWith(
            currentOperation: 'Executing post-run command: $postCmd',
          );
          notifyListeners();
          for (final ch in '$postCmd\n'.split('')) {
            await _hidService.typeCharacter(ch);
            await Future.delayed(const Duration(milliseconds: 18));
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
      });

      // Clear checkpoint on successful completion
      await _storage.deleteCheckpoint(project.id);

      _state = _state.copyWith(
        status: WorkflowExecutionStatus.completed,
        currentOperation: 'Workflow completed successfully.',
        canResume: false,
      );
      notifyListeners();
    } catch (e) {
      _state = _state.copyWith(
        status: WorkflowExecutionStatus.failed,
        errorMessage: e.toString(),
        canResume: true,
      );
      notifyListeners();
    }
  }

  Future<void> _executeStep(int index, Future<void> Function() action) async {
    final updatedSteps = List<WorkflowStep>.from(_state.steps);
    updatedSteps[index] = updatedSteps[index].copyWith(isInProgress: true);
    _state = _state.copyWith(steps: updatedSteps, currentStepIndex: index);
    notifyListeners();

    try {
      await action();
      updatedSteps[index] = updatedSteps[index].copyWith(
        isInProgress: false,
        isCompleted: true,
      );
      _state = _state.copyWith(steps: updatedSteps);
      notifyListeners();
    } catch (e) {
      updatedSteps[index] = updatedSteps[index].copyWith(
        isInProgress: false,
        hasFailed: true,
        error: e.toString(),
      );
      _state = _state.copyWith(steps: updatedSteps);
      notifyListeners();
      rethrow;
    }
  }

  /// Pause current workflow
  void pause() {
    _cadenceEngine.pause();
    _state = _state.copyWith(
      status: WorkflowExecutionStatus.paused,
      canResume: true,
      currentOperation: 'Workflow paused by user.',
    );
    notifyListeners();
  }

  /// Resume paused workflow
  void resume() {
    _cadenceEngine.resume();
    _state = _state.copyWith(
      status: WorkflowExecutionStatus.inProgress,
      currentOperation: 'Resuming workflow...',
    );
    notifyListeners();
  }

  /// Cancel and emergency release
  Future<void> cancel() async {
    _isCancelled = true;
    await _cadenceEngine.cancel();
    _state = _state.copyWith(
      status: WorkflowExecutionStatus.cancelled,
      currentOperation: 'Workflow cancelled.',
      canResume: true,
    );
    notifyListeners();
  }

  /// Emergency panic release button
  Future<void> emergencyPanicRelease() async {
    await _cadenceEngine.emergencyStop();
    _state = _state.copyWith(
      currentOperation: 'Emergency release sent: All keys released.',
    );
    notifyListeners();
  }

  /// Type a custom command string directly into PC with human cadence
  Future<void> typeQuickCommand(String command, {bool pressEnter = true}) async {
    final toType = pressEnter ? '$command\n' : command;
    for (final ch in toType.split('')) {
      await _hidService.typeCharacter(ch);
      await Future.delayed(const Duration(milliseconds: 14));
    }
  }

  /// Send a specific keyboard shortcut chord (e.g. Ctrl+~ or Ctrl+S)
  Future<void> sendShortcut({
    required int hidCode,
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
    bool meta = false,
  }) async {
    await _hidService.sendKeyChord(
      hidCode: hidCode,
      ctrl: ctrl,
      alt: alt,
      shift: shift,
      meta: meta,
    );
  }

  @override
  void dispose() {
    _typingSubscription?.cancel();
    super.dispose();
  }
}
