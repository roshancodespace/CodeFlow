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
  final int
  targetCps; // 2 - 60 characters per second (default 6 CPS: ~45-60 WPM)
  final int focusDelaySeconds; // 1 - 10 seconds
  final int newlinePauseMs; // 50 - 800 ms
  final bool humanJitterEnabled; // Box-Muller Gaussian variance
  final bool humanMistakesEnabled; // Randomized typos & backspace corrections
  final int mistakeProbabilityPercent; // 1 - 10 percent chance of mistake
  final bool thinkingPausesEnabled; // Syntax and thought pauses
  final bool burstCadenceEnabled; // Motor-chunk burst typing with cognitive pauses
  final bool deterministicTestMode; // Fixed exact intervals for testing

  const CadenceConfig({
    this.targetCps = 6,
    this.focusDelaySeconds = 3,
    this.newlinePauseMs = 350,
    this.humanJitterEnabled = true,
    this.humanMistakesEnabled = true,
    this.mistakeProbabilityPercent = 3,
    this.thinkingPausesEnabled = true,
    this.burstCadenceEnabled = true,
    this.deterministicTestMode = false,
  });

  CadenceConfig copyWith({
    int? targetCps,
    int? focusDelaySeconds,
    int? newlinePauseMs,
    bool? humanJitterEnabled,
    bool? humanMistakesEnabled,
    int? mistakeProbabilityPercent,
    bool? thinkingPausesEnabled,
    bool? burstCadenceEnabled,
    bool? deterministicTestMode,
  }) {
    return CadenceConfig(
      targetCps: targetCps ?? this.targetCps,
      focusDelaySeconds: focusDelaySeconds ?? this.focusDelaySeconds,
      newlinePauseMs: newlinePauseMs ?? this.newlinePauseMs,
      humanJitterEnabled: humanJitterEnabled ?? this.humanJitterEnabled,
      humanMistakesEnabled: humanMistakesEnabled ?? this.humanMistakesEnabled,
      mistakeProbabilityPercent:
          mistakeProbabilityPercent ?? this.mistakeProbabilityPercent,
      thinkingPausesEnabled:
          thinkingPausesEnabled ?? this.thinkingPausesEnabled,
      burstCadenceEnabled: burstCadenceEnabled ?? this.burstCadenceEnabled,
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
  }) : _hidService = hidService,
       _random = random ?? Random();

  Stream<TypingProgress> get progressStream => _progressController.stream;
  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;
  bool get isCancelled => _isCancelled;

  /// QWERTY adjacent key map for generating realistic human typos
  static const Map<String, List<String>> _adjacentKeys = {
    'a': ['s', 'q', 'z', 'w'],
    'b': ['v', 'g', 'n', 'h'],
    'c': ['x', 'd', 'v'],
    'd': ['s', 'e', 'f', 'c', 'x'],
    'e': ['w', 'r', 'd', 's'],
    'f': ['d', 'r', 'g', 'v', 'c'],
    'g': ['f', 't', 'h', 'b', 'v'],
    'h': ['g', 'y', 'j', 'n', 'b'],
    'i': ['u', 'o', 'k', 'j'],
    'j': ['h', 'u', 'k', 'm', 'n'],
    'k': ['j', 'i', 'l', 'm'],
    'l': ['k', 'o', 'p'],
    'm': ['n', 'j', 'k'],
    'n': ['b', 'h', 'j', 'm'],
    'o': ['i', 'p', 'l', 'k'],
    'p': ['o', 'l'],
    'q': ['w', 'a', 's'],
    'r': ['e', 't', 'f', 'd'],
    's': ['a', 'w', 'd', 'z', 'x'],
    't': ['r', 'y', 'g', 'f'],
    'u': ['y', 'i', 'j', 'h'],
    'v': ['c', 'f', 'b', 'g'],
    'w': ['q', 'e', 's', 'a'],
    'x': ['z', 's', 'c', 'd'],
    'y': ['t', 'u', 'h', 'g'],
    'z': ['a', 's', 'x'],
    '1': ['2', 'q'],
    '2': ['1', '3', 'w'],
    '3': ['2', '4', 'e'],
    '4': ['3', '5', 'r'],
    '5': ['4', '6', 't'],
    '6': ['5', '7', 'y'],
    '7': ['6', '8', 'u'],
    '8': ['7', '9', 'i'],
    '9': ['8', '0', 'o'],
    '0': ['9', '-', 'p'],
  };

  /// Random burst length: 3-5 chars (e.g. 4 letters fast), 6-9 chars (full word fast), or 10-14 chars (2-3 words fast)
  int _pickNextBurstLength() {
    final roll = _random.nextInt(100);
    if (roll < 45) {
      // 3 to 5 characters (e.g. 4 letters fast)
      return 3 + _random.nextInt(3);
    } else if (roll < 80) {
      // 6 to 9 characters (full word fast)
      return 6 + _random.nextInt(4);
    } else {
      // 10 to 14 characters (2-3 words fast flow)
      return 10 + _random.nextInt(5);
    }
  }

  /// Intra-burst fast keystroke delay (14 - 26 CPS)
  double _calculateIntraBurstDelayMs() {
    final burstCps = (config.targetCps * 2.8).clamp(14, 28);
    final baseMs = 1000.0 / burstCps;
    if (config.deterministicTestMode || !config.humanJitterEnabled) {
      return baseMs;
    }
    // Subtle human Gaussian jitter
    final u1 = max(1e-7, _random.nextDouble());
    final u2 = _random.nextDouble();
    final z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
    final jitter = (z0 * baseMs * 0.18).clamp(-baseMs * 0.35, baseMs * 0.35);
    return max(20.0, baseMs + jitter);
  }

  /// Calculate delay between keystrokes with Box-Muller Gaussian jitter (linear fallback)
  double _calculateNextDelayMs() {
    final baseIntervalMs = 1000.0 / config.targetCps.clamp(2, 60);
    if (config.deterministicTestMode || !config.humanJitterEnabled) {
      return baseIntervalMs;
    }

    // Box-Muller transform for normal distribution
    final u1 = max(1e-7, _random.nextDouble());
    final u2 = _random.nextDouble();
    final z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);

    // Standard deviation is ~18% of base interval, bounded between -35% and +35%
    final stdDev = baseIntervalMs * 0.18;
    final jitter = (z0 * stdDev).clamp(
      -baseIntervalMs * 0.35,
      baseIntervalMs * 0.35,
    );

    return max(15.0, baseIntervalMs + jitter);
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
  Future<void> executeFocusDelay({
    void Function(int remainingSeconds)? onTick,
  }) async {
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
    int burstRemaining = _pickNextBurstLength();
    int charsSinceThoughtPause = 0;

    try {
      while (currentOffset < totalChars) {
        if (_isCancelled) break;

        // Handle pause
        if (_isPaused && _pauseCompleter != null) {
          _progressController.add(
            TypingProgress(
              fileIndex: fileIndex,
              totalFiles: totalFiles,
              charOffset: currentOffset,
              totalChars: totalChars,
              currentFileName: fileName,
              progressPercent: currentOffset / totalChars,
              isPaused: true,
            ),
          );
          await _pauseCompleter!.future;
          if (_isCancelled) break;
        }

        final char = content[currentOffset];

        // 1. Realistic human mistake & backspace auto-correction
        final isAlphaNumeric = RegExp(r'^[a-zA-Z0-9]$').hasMatch(char);
        final shouldMakeMistake =
            !config.deterministicTestMode &&
            config.humanMistakesEnabled &&
            isAlphaNumeric &&
            _random.nextInt(100) < config.mistakeProbabilityPercent;

        if (shouldMakeMistake) {
          final lower = char.toLowerCase();
          final isUpper = char != lower && char.toUpperCase() == char;
          final candidates = _adjacentKeys[lower] ?? ['s', 'd', 'e'];
          var wrongChar = candidates[_random.nextInt(candidates.length)];
          if (isUpper) wrongChar = wrongChar.toUpperCase();

          // Type accidental adjacent key
          await _hidService.typeCharacter(wrongChar);
          if (_isCancelled) break;

          // 15% chance user typed a 2nd accidental key before noticing
          final isDoubleMistake = _random.nextDouble() < 0.15;
          if (isDoubleMistake) {
            final secondCandidates =
                _adjacentKeys[wrongChar.toLowerCase()] ?? candidates;
            var secondWrong =
                secondCandidates[_random.nextInt(secondCandidates.length)];
            if (isUpper) secondWrong = secondWrong.toUpperCase();
            await Future.delayed(
              Duration(milliseconds: 60 + _random.nextInt(70)),
            );
            if (_isCancelled) break;
            await _hidService.typeCharacter(secondWrong);
            if (_isCancelled) break;
          }

          // Human reaction delay: "oops, noticed mistake"
          await Future.delayed(
            Duration(milliseconds: 180 + _random.nextInt(200)),
          );
          if (_isCancelled) break;

          // Press Backspace to erase mistake
          await _hidService.sendKeyPress(HidScancodes.backspace);
          if (_isCancelled) break;

          if (isDoubleMistake) {
            await Future.delayed(
              Duration(milliseconds: 70 + _random.nextInt(60)),
            );
            if (_isCancelled) break;
            await _hidService.sendKeyPress(HidScancodes.backspace);
            if (_isCancelled) break;
          }

          // Human correction pause before typing correct character
          await Future.delayed(
            Duration(milliseconds: 90 + _random.nextInt(110)),
          );
          if (_isCancelled) break;
        }

        // 2. Type correct character
        await _hidService.typeCharacter(char);

        currentOffset++;
        charsSinceThoughtPause++;
        burstRemaining--;

        // Emit progress periodically
        if (currentOffset % 5 == 0 || currentOffset == totalChars) {
          _progressController.add(
            TypingProgress(
              fileIndex: fileIndex,
              totalFiles: totalFiles,
              charOffset: currentOffset,
              totalChars: totalChars,
              currentFileName: fileName,
              progressPercent: currentOffset / totalChars,
              isPaused: false,
            ),
          );
        }

        // 3. Cadence and human thinking pauses
        if (config.deterministicTestMode) {
          if (char == '\n') {
            await Future.delayed(
              Duration(milliseconds: config.newlinePauseMs),
            );
          } else {
            final delayMs = _calculateNextDelayMs();
            await Future.delayed(Duration(milliseconds: delayMs.round()));
          }
        } else if (!config.burstCadenceEnabled) {
          // Fallback classic cadence
          if (char == '\n') {
            final pauseMs =
                (config.newlinePauseMs + (_random.nextInt(140) - 50)).clamp(
                  80,
                  800,
                );
            await Future.delayed(Duration(milliseconds: pauseMs));
          } else {
            if (config.thinkingPausesEnabled) {
              if (char == ';' || char == '{' || char == '}' || char == ')') {
                final syntaxPause = 140 + _random.nextInt(220);
                await Future.delayed(Duration(milliseconds: syntaxPause));
              } else if (_random.nextInt(1000) < 15) {
                final thoughtPause = 600 + _random.nextInt(700);
                await Future.delayed(Duration(milliseconds: thoughtPause));
              }
            }
            final delayMs = _calculateNextDelayMs();
            await Future.delayed(Duration(milliseconds: delayMs.round()));
          }
        } else {
          // HYPER-REALISTIC HUMAN BURST & COGNITIVE PAUSE CADENCE
          if (char == '\n') {
            // Line break inspection pause
            final pauseMs =
                (config.newlinePauseMs + (_random.nextInt(180) - 40)).clamp(
                  120,
                  900,
                );
            await Future.delayed(Duration(milliseconds: pauseMs));
            burstRemaining = _pickNextBurstLength();
          } else if (char == ' ') {
            // Word boundary: check for deep thought pause or word glance hesitation
            if (config.thinkingPausesEnabled &&
                ((charsSinceThoughtPause > 40 && _random.nextDouble() < 0.22) ||
                    _random.nextDouble() < 0.025)) {
              // Deep developer cognitive pause ("thinking about next variable/method")
              charsSinceThoughtPause = 0;
              final thoughtMs = 850 + _random.nextInt(1300);
              await Future.delayed(Duration(milliseconds: thoughtMs));
              burstRemaining = _pickNextBurstLength();
            } else if (burstRemaining <= 0 || _random.nextDouble() < 0.35) {
              // Inter-word glance / cognitive retrieval pause (140ms - 380ms)
              final interWordMs = 130 + _random.nextInt(250);
              await Future.delayed(Duration(milliseconds: interWordMs));
              burstRemaining = _pickNextBurstLength();
            } else {
              // Intra-burst space (rapid 2-3 word flow)
              final intraMs = _calculateIntraBurstDelayMs();
              await Future.delayed(Duration(milliseconds: intraMs.round()));
            }
          } else if (char == ';' ||
              char == '{' ||
              char == '}' ||
              char == ')' ||
              char == ']') {
            // Syntax processing pause
            if (config.thinkingPausesEnabled) {
              final syntaxMs = 180 + _random.nextInt(260);
              await Future.delayed(Duration(milliseconds: syntaxMs));
            } else {
              final intraMs = _calculateIntraBurstDelayMs();
              await Future.delayed(Duration(milliseconds: intraMs.round()));
            }
            burstRemaining = _pickNextBurstLength();
          } else if (burstRemaining <= 0) {
            // End of fast burst reached (e.g. after 4 letters or word): pause to glance/think
            final chunkPauseMs = 150 + _random.nextInt(280);
            await Future.delayed(Duration(milliseconds: chunkPauseMs));
            burstRemaining = _pickNextBurstLength();
          } else {
            // Fast intra-burst keystroke (motor clatter, 14 - 26 CPS)
            final intraMs = _calculateIntraBurstDelayMs();
            await Future.delayed(Duration(milliseconds: intraMs.round()));
          }
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
