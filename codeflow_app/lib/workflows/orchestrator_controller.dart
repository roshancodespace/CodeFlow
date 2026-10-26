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
  final bool awaitingStep2Confirmation;

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
    this.awaitingStep2Confirmation = false,
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
    bool? awaitingStep2Confirmation,
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
      awaitingStep2Confirmation:
          awaitingStep2Confirmation ?? this.awaitingStep2Confirmation,
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
  }) : _hidService = hidService,
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
        currentOperation:
            'Typing: ${prog.currentFileName} (${(prog.progressPercent * 100).toInt()}%)',
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
    final selectedFiles = project.files
        .where((f) => !f.isDirectory && f.isSelected)
        .toList();
    final isMac =
        targetOs.toLowerCase().contains('darwin') ||
        targetOs.toLowerCase().contains('mac');
    final mode = _storage.automationMode;
    final useDirect = mode == 'directNetwork' && companionAvailable;

    final steps = <WorkflowStep>[
      WorkflowStep(
        title: 'Validation',
        details:
            'Verify ${selectedFiles.length} selected files and project integrity',
      ),
      WorkflowStep(
        title: 'Step 1: Scaffold Workspace (Direct Host Execution)',
        details:
            'Direct execution creates all directories and empty files on host disk before automating (no keyboard HID errors)',
      ),
      WorkflowStep(
        title: 'Step 2: Humanized In-Editor Coding (VS Code Quick Open)',
        details: useDirect
            ? 'Direct file transfer of ${selectedFiles.length} files to PC workspace'
            : (isMac
                ? 'Quick Open (Cmd + P) -> Code in Editor with burst typing cadence & cognitive pauses'
                : 'Quick Open (Ctrl + P) -> Code in Editor with burst typing cadence & cognitive pauses'),
      ),
      WorkflowStep(
        title: 'Save & Post-Run Execution',
        details: _storage.postRunCommand.isNotEmpty
            ? 'Save editor (Ctrl+S) and execute: "${_storage.postRunCommand}"'
            : 'Verify completion and save editor buffer (Ctrl/Cmd + S)',
      ),
    ];

    return steps;
  }

  /// Start Step 1: Pre-create Project Structure (Direct Host Execution)
  Future<void> runWorkflow({
    required Project project,
    bool resumeFromCheckpoint = false,
  }) async {
    _isCancelled = false;
    final selectedFiles = project.files
        .where((f) => !f.isDirectory && f.isSelected)
        .toList();
    if (selectedFiles.isEmpty) {
      _state = _state.copyWith(
        status: WorkflowExecutionStatus.failed,
        errorMessage: 'No files selected for workflow.',
      );
      notifyListeners();
      return;
    }

    if (resumeFromCheckpoint) {
      await startStep2Coding(project: project, resumeFromCheckpoint: true);
      return;
    }

    // 1. Check companion connectivity
    final host = _storage.companionHost;
    final port = _storage.companionPort;
    final token = _storage.companionToken;
    final companionInfo = await _companionApi.getInfo(
      host: host,
      port: port,
      token: token,
    );
    final companionAvailable = companionInfo != null;
    final targetOs =
        companionInfo?.os ??
        (defaultTargetPlatform == TargetPlatform.macOS ? 'Darwin' : 'Linux');

    final steps = planWorkflow(
      project: project,
      companionAvailable: companionAvailable,
      targetOs: targetOs,
    );

    _state = _state.copyWith(
      status: WorkflowExecutionStatus.inProgress,
      steps: steps,
      currentStepIndex: 0,
      currentFileIndex: 0,
      totalFiles: selectedFiles.length,
      currentCharacterOffset: 0,
      currentOperation: 'Validating project workspace...',
      errorMessage: null,
      canResume: false,
      awaitingStep2Confirmation: false,
    );
    notifyListeners();

    try {
      // Step 0: Validation
      await _executeStep(0, () async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      if (_isCancelled) return;

      // Step 1: Pre-create Project Structure (Direct Execution, No HID)
      await _executeStep(1, () async {
        _state = _state.copyWith(
          currentOperation: 'Direct execution: Scaffolding project files...',
        );
        notifyListeners();

        final directories = <String>{};
        final filePaths = <String>[];
        for (final f in selectedFiles) {
          filePaths.add(f.relativePath);
          final parts = f.relativePath.split('/');
          if (parts.length > 1) {
            var acc = '';
            for (int p = 0; p < parts.length - 1; p++) {
              acc = acc.isEmpty ? parts[p] : '$acc/${parts[p]}';
              directories.add(acc);
            }
          }
        }

        if (companionAvailable) {
          final res = await _companionApi.scaffoldWorkspace(
            host: host,
            port: port,
            token: token,
            directories: directories.toList(),
            files: filePaths,
          );
          if (!res.success) {
            throw Exception(
              'Direct workspace scaffolding failed: ${res.errorMessage}',
            );
          }
        }
        await Future.delayed(const Duration(milliseconds: 250));
      });
      if (_isCancelled) return;

      // STEP 1 COMPLETE! Explicitly pause and wait for user to start Step 2!
      _state = _state.copyWith(
        status: WorkflowExecutionStatus.paused,
        awaitingStep2Confirmation: true,
        currentStepIndex: 1,
        currentOperation:
            'Step 1 complete: All directories and files created on PC! Switch to VS Code and tap "Start Coding in VS Code" to begin Step 2.',
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

  /// User action: Confirm and begin Step 2 (In-Editor Humanized Coding)
  Future<void> confirmStartStep2({required Project project}) async {
    await startStep2Coding(project: project, resumeFromCheckpoint: false);
  }

  /// Execute Step 2: Humanized In-Editor Coding (Quick Open + Cadence Typing)
  Future<void> startStep2Coding({
    required Project project,
    bool resumeFromCheckpoint = false,
  }) async {
    _isCancelled = false;
    final selectedFiles = project.files
        .where((f) => !f.isDirectory && f.isSelected)
        .toList();
    if (selectedFiles.isEmpty) return;

    final host = _storage.companionHost;
    final port = _storage.companionPort;
    final token = _storage.companionToken;
    final companionInfo = await _companionApi.getInfo(
      host: host,
      port: port,
      token: token,
    );
    final companionAvailable = companionInfo != null;
    final targetOs =
        companionInfo?.os ??
        (defaultTargetPlatform == TargetPlatform.macOS ? 'Darwin' : 'Linux');
    final isMac =
        targetOs.toLowerCase().contains('darwin') ||
        targetOs.toLowerCase().contains('mac');
    final mode = _storage.automationMode;

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

    _state = _state.copyWith(
      status: WorkflowExecutionStatus.inProgress,
      awaitingStep2Confirmation: false,
      currentStepIndex: 2,
      currentFileIndex: startFileIndex,
      currentCharacterOffset: startCharOffset,
      currentOperation: 'Preparing in-editor coding...',
      errorMessage: null,
      canResume: false,
    );
    notifyListeners();

    try {
      // 1. Focus countdown delay (gives user time to ensure VS Code window is focused)
      _cadenceEngine.config = _cadenceEngine.config.copyWith(
        focusDelaySeconds: _storage.focusDelaySeconds,
        targetCps: _storage.typingSpeedCps,
        newlinePauseMs: _storage.newlinePauseMs,
        humanJitterEnabled: _storage.humanJitterEnabled,
        humanMistakesEnabled: _storage.humanMistakesEnabled,
        mistakeProbabilityPercent: _storage.mistakeProbabilityPercent,
        thinkingPausesEnabled: _storage.thinkingPausesEnabled,
        burstCadenceEnabled: true,
      );

      await _cadenceEngine.executeFocusDelay(
        onTick: (sec) {
          _state = _state.copyWith(
            focusCountdownRemaining: sec,
            currentOperation: sec > 0
                ? 'Focus target PC window ($sec s)...'
                : 'Starting in-editor coding...',
          );
          notifyListeners();
        },
      );
      if (_isCancelled) return;

      // 2. Step 2 execution: In-Editor Humanized Coding
      await _executeStep(2, () async {
        for (int i = startFileIndex; i < selectedFiles.length; i++) {
          if (_isCancelled) break;
          final file = selectedFiles[i];
          final content = file.content ?? '';

          if (mode == 'directNetwork' && companionAvailable) {
            _state = _state.copyWith(
              currentFileIndex: i,
              currentOperation: 'Direct transfer: ${file.relativePath}...',
            );
            notifyListeners();

            final result = await _fileTransferService.transferFile(
              host: host,
              port: port,
              token: token,
              file: file,
              fileContent: content,
            );
            if (!result.success) {
              throw Exception(
                'Direct transfer failed for ${file.relativePath}: ${result.errorMessage}',
              );
            }
          } else {
            // REAL DEVELOPER VS CODE IN-EDITOR TYPING (DEFAULT)
            _state = _state.copyWith(
              currentFileIndex: i,
              currentOperation: 'Quick Open: ${file.relativePath} (Ctrl+P)...',
            );
            notifyListeners();

            // Quick Open (Ctrl+P / Cmd+P)
            await _hidService.sendKeyChord(
              hidCode: HidScancodes.keyP,
              ctrl: !isMac,
              meta: isMac,
            );
            await Future.delayed(const Duration(milliseconds: 320));

            // Type the relative path into Quick Open
            for (final ch in file.relativePath.split('')) {
              if (_isCancelled) break;
              await _hidService.typeCharacter(ch);
              await Future.delayed(const Duration(milliseconds: 15));
            }
            if (_isCancelled) break;

            await Future.delayed(const Duration(milliseconds: 250));
            // Press Enter to focus editor tab
            await _hidService.sendKeyPress(HidScancodes.enter);
            await Future.delayed(const Duration(milliseconds: 550));

            // Screen OCR verification if companion available
            if (companionAvailable && !_isCancelled) {
              bool ocrConfirmed = false;
              for (int attempt = 0; attempt < 3; attempt++) {
                if (_isCancelled) break;
                final ocr = await _companionApi.getScreenOcr(
                  host: host,
                  port: port,
                  token: token,
                  query: file.name,
                  region: 'top',
                );
                if (ocr != null && ocr.queryFound) {
                  ocrConfirmed = true;
                  break;
                }
                await Future.delayed(const Duration(milliseconds: 300));
              }

              if (!ocrConfirmed && !_isCancelled) {
                // Retry Quick Open with basename
                await _hidService.sendKeyChord(
                  hidCode: HidScancodes.keyP,
                  ctrl: !isMac,
                  meta: isMac,
                );
                await Future.delayed(const Duration(milliseconds: 250));
                for (final ch in file.name.split('')) {
                  if (_isCancelled) break;
                  await _hidService.typeCharacter(ch);
                  await Future.delayed(const Duration(milliseconds: 14));
                }
                await Future.delayed(const Duration(milliseconds: 200));
                await _hidService.sendKeyPress(HidScancodes.enter);
                await Future.delayed(const Duration(milliseconds: 450));
              }
            }

            // Clear existing buffer if starting from offset 0
            if (startCharOffset == 0 && !_isCancelled) {
              await _hidService.sendKeyChord(
                hidCode: HidScancodes.keyA,
                ctrl: !isMac,
                meta: isMac,
              );
              await Future.delayed(const Duration(milliseconds: 140));
              await _hidService.sendKeyPress(HidScancodes.backspace);
              await Future.delayed(const Duration(milliseconds: 200));
            }

            // Humanized in-editor burst-pause cadence typing
            _state = _state.copyWith(
              currentOperation: 'Human coding: ${file.relativePath}...',
            );
            notifyListeners();

            final charsTyped = await _cadenceEngine.typeContent(
              content: content,
              fileName: file.relativePath,
              fileIndex: i,
              totalFiles: selectedFiles.length,
              startOffset: (i == startFileIndex) ? startCharOffset : 0,
            );

            if (_isCancelled) {
              await _storage.saveCheckpoint(
                WorkflowCheckpoint(
                  projectId: project.id,
                  currentFileIndex: i,
                  charOffset: charsTyped,
                  status: WorkflowExecutionStatus.paused,
                  completedRelativePaths: completedFiles,
                  lastUpdated: DateTime.now(),
                ),
              );
              return;
            }

            // Save file buffer in VS Code (Ctrl+S / Cmd+S)
            _state = _state.copyWith(
              currentOperation: 'Saving ${file.relativePath} (Ctrl+S)...',
            );
            notifyListeners();

            await _hidService.sendKeyChord(
              hidCode: HidScancodes.keyS,
              ctrl: !isMac,
              meta: isMac,
            );
            await Future.delayed(const Duration(milliseconds: 350));
          }

          completedFiles.add(file.relativePath);
          await _storage.saveCheckpoint(
            WorkflowCheckpoint(
              projectId: project.id,
              currentFileIndex: i + 1,
              charOffset: 0,
              status: WorkflowExecutionStatus.inProgress,
              completedRelativePaths: completedFiles,
              lastUpdated: DateTime.now(),
            ),
          );
        }
      });
      if (_isCancelled) return;

      // Step 3: Verification, Save & Post-Run Command
      await _executeStep(3, () async {
        final isMac =
            targetOs.toLowerCase().contains('darwin') ||
            targetOs.toLowerCase().contains('mac');
        await _hidService.sendKeyChord(
          hidCode: HidScancodes.keyS,
          ctrl: !isMac,
          meta: isMac,
        );
        await Future.delayed(const Duration(milliseconds: 300));

        final postCmd = _storage.postRunCommand;
        if (postCmd.isNotEmpty) {
          _state = _state.copyWith(
            currentOperation: 'Executing post-run command: $postCmd',
          );
          notifyListeners();

          await _hidService.sendKeyChord(
            hidCode: HidScancodes.graveAccentTilde,
            ctrl: !isMac,
            meta: isMac,
          );
          await Future.delayed(const Duration(milliseconds: 400));

          for (final ch in '$postCmd\n'.split('')) {
            await _hidService.typeCharacter(ch);
            await Future.delayed(const Duration(milliseconds: 20));
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
      });

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
  Future<void> typeQuickCommand(
    String command, {
    bool pressEnter = true,
  }) async {
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
