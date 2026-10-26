import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'bluetooth_hid_service.dart';

/// Progress state emitted by the Cadence Engine during typing.
@immutable
class TypingProgress {
  final int fileIndex;
  final int totalFiles;
  final int charOffset;
  final int totalChars;
  final String currentFileName;
  final double progressPercent;
  final bool isPaused;
  final bool isCancelled;

  const TypingProgress({
    required this.fileIndex,
    required this.totalFiles,
    required this.charOffset,
    required this.totalChars,
    required this.currentFileName,
    required this.progressPercent,
    this.isPaused = false,
    this.isCancelled = false,
  });
}

/// Cadence Configuration
@immutable
class CadenceConfig {
  final int targetCps; // 10 - 80 characters per second
  final int focusDelaySeconds; // 1 - 10 seconds
  final int newlinePauseMs; // 50 - 300 ms
  final bool humanJitterEnabled; // Box-Muller Gaussian variance
  final bool deterministicTestMode; // Fixed exact intervals for testing

  const CadenceConfig({
    this.targetCps = 35,
    this.focusDelaySeconds = 3,
    this.newlinePauseMs = 150,
    this.humanJitterEnabled = true,
    this.deterministicTestMode = false,
  });

  CadenceConfig copyWith({
    int? targetCps,
    int? focusDelaySeconds,
    int? newlinePauseMs,
    bool? humanJitterEnabled,
    bool? deterministicTestMode,
  }) {
    return CadenceConfig(
      targetCps: targetCps ?? this.targetCps,
      focusDelaySeconds: focusDelaySeconds ?? this.focusDelaySeconds,
      newlinePauseMs: newlinePauseMs ?? this.newlinePauseMs,
      humanJitterEnabled: humanJitterEnabled ?? this.humanJitterEnabled,
      deterministicTestMode:
          deterministicTestMode ?? this.deterministicTestMode,
    );
  }
}

/// Typing Cadence Engine simulating human-like keystroke execution over Bluetooth HID.
class TypingCadenceEngine {
  final IBluetoothHidService _hidService;
  final Random _random;

  CadenceConfig config;

  bool _isRunning = false;
  bool _isPaused = false;
  bool _isCancelled = false;

  Completer<void>? _pauseCompleter;
  final StreamController<TypingProgress> _progressController =
      StreamController<TypingProgress>.broadcast();

  TypingCadenceEngine({
    required IBluetoothHidService hidService,
    this.config = const CadenceConfig(),
    Random? random,
  })  : _hidService = hidService,
        _random = random ?? Random();

  Stream<TypingProgress> get progressStream => _progressController.stream;
  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;
  bool get isCancelled => _isCancelled;

  /// Calculate delay between keystrokes with Box-Muller Gaussian jitter
  double _calculateNextDelayMs() {
    final baseIntervalMs = 1000.0 / config.targetCps.clamp(10, 80);
    if (config.deterministicTestMode || !config.humanJitterEnabled) {
      return baseIntervalMs;
    }

    // Box-Muller transform for normal distribution
    final u1 = max(1e-7, _random.nextDouble());
    final u2 = _random.nextDouble();
    final z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);

    // Standard deviation is ~15% of base interval, bounded between -30% and +30%
    final stdDev = baseIntervalMs * 0.15;
    final jitter = (z0 * stdDev).clamp(-baseIntervalMs * 0.35, baseIntervalMs * 0.35);

    return max(5.0, baseIntervalMs + jitter);
  }

  /// Pause typing
  void pause() {
    if (_isRunning && !_isPaused) {
      _isPaused = true;
      _pauseCompleter = Completer<void>();
    }
  }

  /// Resume typing
  void resume() {
    if (_isRunning && _isPaused) {
      _isPaused = false;
      _pauseCompleter?.complete();
      _pauseCompleter = null;
    }
  }

  /// Cancel typing
  Future<void> cancel() async {
    _isCancelled = true;
    _isPaused = false;
    _pauseCompleter?.complete();
    _pauseCompleter = null;
    await emergencyStop();
  }

  /// Emergency Panic Release: Immediately release all keys
  Future<void> emergencyStop() async {
    await _hidService.sendEmergencyRelease();
  }

  /// Run focus countdown delay
  Future<void> executeFocusDelay({void Function(int remainingSeconds)? onTick}) async {
    final totalSeconds = config.focusDelaySeconds.clamp(1, 10);
    for (int s = totalSeconds; s > 0; s--) {
      if (_isCancelled) return;
      onTick?.call(s);
      await Future.delayed(const Duration(seconds: 1));
    }
    onTick?.call(0);
  }

  /// Types a complete string or file content, supporting checkpoint start offset
  Future<int> typeContent({
    required String content,
    required String fileName,
    int fileIndex = 0,
    int totalFiles = 1,
    int startOffset = 0,
  }) async {
    if (content.isEmpty) return 0;
    _isRunning = true;
    _isCancelled = false;
    _isPaused = false;

    int currentOffset = startOffset.clamp(0, content.length);
    final totalChars = content.length;

    try {
      while (currentOffset < totalChars) {
        if (_isCancelled) break;

        // Handle pause
        if (_isPaused && _pauseCompleter != null) {
          _progressController.add(TypingProgress(
            fileIndex: fileIndex,
            totalFiles: totalFiles,
            charOffset: currentOffset,
            totalChars: totalChars,
            currentFileName: fileName,
            progressPercent: currentOffset / totalChars,
            isPaused: true,
          ));
          await _pauseCompleter!.future;
          if (_isCancelled) break;
        }

        final char = content[currentOffset];
        await _hidService.typeCharacter(char);

        currentOffset++;

        // Emit progress periodically
        if (currentOffset % 5 == 0 || currentOffset == totalChars) {
          _progressController.add(TypingProgress(
            fileIndex: fileIndex,
            totalFiles: totalFiles,
            charOffset: currentOffset,
            totalChars: totalChars,
            currentFileName: fileName,
            progressPercent: currentOffset / totalChars,
            isPaused: false,
          ));
        }

        // Delay after newline for IDE auto-formatters & bracket completions
        if (char == '\n') {
          final pauseMs = config.deterministicTestMode
              ? config.newlinePauseMs
              : config.newlinePauseMs.clamp(50, 300);
          await Future.delayed(Duration(milliseconds: pauseMs));
        } else {
          final delayMs = _calculateNextDelayMs();
          await Future.delayed(Duration(milliseconds: delayMs.round()));
        }
      }
    } finally {
      _isRunning = false;
      // Ensure no stuck modifier or key remains
      await _hidService.sendEmergencyRelease();
    }

    return currentOffset;
  }

  void dispose() {
    _progressController.close();
  }
}
