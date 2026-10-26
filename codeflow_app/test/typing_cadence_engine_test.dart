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
  Future<bool> connectHost(String address) async => true;

  @override
  Future<bool> disconnectHost() async => true;

  @override
  Future<List<BluetoothHostDevice>> getPairedDevices() async => [
    connectedHost!,
  ];

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> registerApp() async => true;

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
  Future<void> dispose() async {}
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
  });
}
