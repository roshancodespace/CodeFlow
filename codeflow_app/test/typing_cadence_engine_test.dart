import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:codeflow_app/services/bluetooth_hid_service.dart';
import 'package:codeflow_app/services/typing_cadence_engine.dart';

/// Fake HID Service for deterministic unit testing
class FakeBluetoothHidService implements IBluetoothHidService {
  final List<String> typedCharacters = [];
  final List<List<int>> sentReports = [];
  int emergencyReleaseCount = 0;

  @override
  BluetoothHostDevice? get connectedHost => const BluetoothHostDevice(
    name: 'Test Host',
    address: '00:11:22:33:44:55',
  );

  @override
  Stream<HidConnectionStatus> get connectionStatusStream =>
      Stream.value(HidConnectionStatus.connected);

  @override
  HidConnectionStatus get currentStatus => HidConnectionStatus.connected;

  @override
  List<BluetoothHostDevice> get pairedDevices => [connectedHost!];

  @override
  Future<bool> connectHost(String address) async => true;

  @override
  Future<bool> disconnectHost() async => true;

  @override
  Future<List<BluetoothHostDevice>> getPairedDevices() async => [
    connectedHost!,
  ];

  @override
  Future<BluetoothHostDevice?> getConnectedHost() async => connectedHost;

  @override
  Future<bool> openBluetoothSettings() async => true;

  @override
  Future<void> refreshState() async {}

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> hasPermissions() async => true;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<bool> isBluetoothEnabled() async => true;

  @override
  Future<bool> enableBluetooth() async => true;

  @override
  Future<bool> requestDiscoverable({int duration = 300}) async => true;

  @override
  Future<bool> registerApp({
    String? deviceName,
    String? providerName,
    String? description,
  }) async => true;

  @override
  Future<bool> sendEmergencyRelease() async {
    emergencyReleaseCount++;
    sentReports.add([0, 0, 0, 0, 0, 0, 0, 0]);
    return true;
  }

  @override
  Future<bool> sendKeyChord({
    required int hidCode,
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
    bool meta = false,
  }) async {
    sentReports.add([hidCode]);
    return true;
  }

  @override
  Future<bool> sendKeyPress(int hidCode, {int modifiers = 0}) async {
    sentReports.add([modifiers, 0, hidCode, 0, 0, 0, 0, 0]);
    return true;
  }

  @override
  Future<bool> sendRawReport(List<int> report) async {
    sentReports.add(report);
    return true;
  }

  @override
  Future<bool> typeCharacter(String char) async {
    typedCharacters.add(char);
    return true;
  }

  @override
  Future<bool> unregisterApp() async => true;

  @override
  void dispose() {}
}

void main() {
  group('TypingCadenceEngine Tests', () {
    late FakeBluetoothHidService fakeHid;
    late TypingCadenceEngine engine;

    setUp(() {
      fakeHid = FakeBluetoothHidService();
      engine = TypingCadenceEngine(
        hidService: fakeHid,
        config: const CadenceConfig(
          targetCps: 50,
          focusDelaySeconds: 1,
          newlinePauseMs: 50,
          humanJitterEnabled: false,
          deterministicTestMode: true,
        ),
      );
    });

    tearDown(() {
      engine.dispose();
    });

    test('types ASCII string accurately character by character', () async {
      const codeSnippet = 'int x = 42;\n';
      final offset = await engine.typeContent(
        content: codeSnippet,
        fileName: 'test.dart',
      );

      expect(offset, equals(codeSnippet.length));
      expect(fakeHid.typedCharacters.join(''), equals(codeSnippet));
      // Upon completion, emergency release is called to ensure no stuck keys
      expect(fakeHid.emergencyReleaseCount, greaterThanOrEqualTo(1));
    });

    test('supports start offset for checkpoint resume', () async {
      const codeSnippet = 'print("hello");';
      const startOffset = 7; // Start at "hello"
      final offset = await engine.typeContent(
        content: codeSnippet,
        fileName: 'test.dart',
        startOffset: startOffset,
      );

      expect(offset, equals(codeSnippet.length));
      expect(fakeHid.typedCharacters.join(''), equals('hello");'));
    });

    test('emergencyStop sends HID empty release report immediately', () async {
      await engine.emergencyStop();
      expect(fakeHid.emergencyReleaseCount, equals(1));
      expect(fakeHid.sentReports.last, equals([0, 0, 0, 0, 0, 0, 0, 0]));
    });

    test('pause and resume execution', () async {
      const codeSnippet = 'abcdefghij';
      bool pausedReported = false;

      final sub = engine.progressStream.listen((prog) {
        if (prog.isPaused) pausedReported = true;
      });

      final typeFuture = engine.typeContent(
        content: codeSnippet,
        fileName: 'test.dart',
      );

      // Trigger pause quickly
      await Future.delayed(const Duration(milliseconds: 20));
      engine.pause();
      expect(engine.isPaused, isTrue);

      await Future.delayed(const Duration(milliseconds: 50));
      engine.resume();
      expect(engine.isPaused, isFalse);

      final result = await typeFuture;
      expect(result, equals(codeSnippet.length));
      expect(fakeHid.typedCharacters.length, equals(codeSnippet.length));
      expect(pausedReported, isTrue);

      await sub.cancel();
    });

    test('cancel halts execution cleanly', () async {
      const longSnippet = 'Very long string that should be cancelled early';
      final typeFuture = engine.typeContent(
        content: longSnippet,
        fileName: 'test.dart',
      );

      await Future.delayed(const Duration(milliseconds: 30));
      await engine.cancel();

      expect(engine.isCancelled, isTrue);
      final typedCount = await typeFuture;
      expect(typedCount, lessThan(longSnippet.length));
      expect(fakeHid.emergencyReleaseCount, greaterThanOrEqualTo(1));
    });

    test(
      'CadenceConfig default values reflect real human developer typing',
      () {
        const defaultConfig = CadenceConfig();
        expect(defaultConfig.targetCps, equals(6));
        expect(defaultConfig.humanMistakesEnabled, isTrue);
        expect(defaultConfig.mistakeProbabilityPercent, equals(3));
        expect(defaultConfig.thinkingPausesEnabled, isTrue);
        expect(defaultConfig.burstCadenceEnabled, isTrue);
        expect(defaultConfig.deterministicTestMode, isFalse);
      },
    );

    test('burst cadence types multiple words in human flow bursts', () async {
      final burstHid = FakeBluetoothHidService();
      final burstEngine = TypingCadenceEngine(
        hidService: burstHid,
        config: const CadenceConfig(
          targetCps: 50,
          burstCadenceEnabled: true,
          humanJitterEnabled: false,
          humanMistakesEnabled: false,
          thinkingPausesEnabled: false,
          deterministicTestMode: true,
        ),
      );

      const phrase = 'final String name = "CodeFlow";\n';
      final offset = await burstEngine.typeContent(
        content: phrase,
        fileName: 'model.dart',
      );

      expect(offset, equals(phrase.length));
      expect(burstHid.typedCharacters.join(''), equals(phrase));
      burstEngine.dispose();
    });

    test(
      'generates adjacent typo, backspace, and correct character when mistakes enabled',
      () async {
        final mistakeHid = FakeBluetoothHidService();
        final mistakeEngine = TypingCadenceEngine(
          hidService: mistakeHid,
          config: const CadenceConfig(
            targetCps: 60,
            humanJitterEnabled: false,
            humanMistakesEnabled: true,
            mistakeProbabilityPercent: 100, // force mistake on every char
            thinkingPausesEnabled: false,
            deterministicTestMode: false,
          ),
        );

        // Type a single alphanumeric character 'e'
        final offset = await mistakeEngine.typeContent(
          content: 'e',
          fileName: 'test.dart',
        );

        expect(offset, equals(1));
        // First typed character was wrong key, last typed character is the correct key 'e'
        expect(mistakeHid.typedCharacters.length, greaterThanOrEqualTo(2));
        expect(mistakeHid.typedCharacters.last, equals('e'));
        // Backspace was sent to fix the mistake
        final backspaceSent = mistakeHid.sentReports.any(
          (r) => r.length >= 3 && r[2] == HidScancodes.backspace,
        );
        expect(backspaceSent, isTrue);

        mistakeEngine.dispose();
      },
    );
  });
}
