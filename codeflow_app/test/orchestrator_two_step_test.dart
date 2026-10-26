import 'package:flutter_test/flutter_test.dart';
import 'package:codeflow_app/models/project.dart';
import 'package:codeflow_app/models/source_file.dart';
import 'package:codeflow_app/models/workflow_checkpoint.dart';
import 'package:codeflow_app/services/companion_api_service.dart';
import 'package:codeflow_app/workflows/orchestrator_controller.dart';
import 'package:codeflow_app/services/bluetooth_hid_service.dart';
import 'package:codeflow_app/services/file_transfer_service.dart';
import 'package:codeflow_app/services/typing_cadence_engine.dart';
import 'package:codeflow_app/core/storage/local_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockBluetoothHidService implements IBluetoothHidService {
  final List<String> typed = [];
  final List<int> chords = [];

  @override
  BluetoothHostDevice? get connectedHost => null;
  @override
  Stream<HidConnectionStatus> get connectionStatusStream =>
      Stream.value(HidConnectionStatus.connected);
  @override
  HidConnectionStatus get currentStatus => HidConnectionStatus.connected;
  @override
  List<BluetoothHostDevice> get pairedDevices => const [];

  @override
  Future<bool> connectHost(String address) async => true;
  @override
  Future<bool> disconnectHost() async => true;
  @override
  Future<List<BluetoothHostDevice>> getPairedDevices() async => const [];
  @override
  Future<BluetoothHostDevice?> getConnectedHost() async => null;
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
  Future<bool> sendEmergencyRelease() async => true;
  @override
  Future<bool> sendKeyChord({
    required int hidCode,
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
    bool meta = false,
  }) async {
    chords.add(hidCode);
    return true;
  }
  @override
  Future<bool> sendKeyPress(int hidCode, {int modifiers = 0}) async => true;
  @override
  Future<bool> sendRawReport(List<int> report) async => true;
  @override
  Future<bool> typeCharacter(String char) async {
    typed.add(char);
    return true;
  }
  @override
  Future<bool> unregisterApp() async => true;
  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Orchestrator Two-Step Architecture Tests', () {
    late LocalStorageService storage;
    late MockBluetoothHidService fakeHid;
    late TypingCadenceEngine cadenceEngine;
    late OrchestratorController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      storage = LocalStorageService(prefs);
      fakeHid = MockBluetoothHidService();
      cadenceEngine = TypingCadenceEngine(
        hidService: fakeHid,
        config: const CadenceConfig(
          deterministicTestMode: true,
          focusDelaySeconds: 1,
        ),
      );

      controller = OrchestratorController(
        hidService: fakeHid,
        companionApi: CompanionApiService(),
        fileTransferService: FileTransferService(),
        cadenceEngine: cadenceEngine,
        storage: storage,
      );
    });

    tearDown(() {
      controller.dispose();
      cadenceEngine.dispose();
    });

    test('planWorkflow produces 2-step direct scaffold architecture', () {
      final now = DateTime.now();
      final project = Project(
        id: 'test_proj',
        name: 'Test Project',
        rootPath: '/path/test',
        createdAt: now,
        updatedAt: now,
        files: const [
          SourceFile(
            path: '/path/test/lib/main.dart',
            relativePath: 'lib/main.dart',
            sizeInBytes: 100,
            extension: '.dart',
            isSelected: true,
            content: 'void main() {}',
          ),
          SourceFile(
            path: '/path/test/lib/screens/home.dart',
            relativePath: 'lib/screens/home.dart',
            sizeInBytes: 150,
            extension: '.dart',
            isSelected: true,
            content: 'class HomeScreen {}',
          ),
        ],
      );

      final steps = controller.planWorkflow(
        project: project,
        companionAvailable: true,
        targetOs: 'Linux',
      );

      expect(steps.length, equals(4));
      expect(steps[0].title, equals('Validation'));
      expect(steps[1].title, contains('Step 1: Scaffold Workspace (Direct Host Execution)'));
      expect(steps[2].title, contains('Step 2: Humanized In-Editor Coding (VS Code Quick Open)'));
      expect(steps[3].title, equals('Save & Post-Run Execution'));
    });

    test('ScaffoldResult model correctly models result of host pre-creation', () {
      const successResult = ScaffoldResult(
        success: true,
        directoriesCreated: 5,
        filesCreated: 12,
      );
      expect(successResult.success, isTrue);
      expect(successResult.directoriesCreated, equals(5));
      expect(successResult.filesCreated, equals(12));
      expect(successResult.errorMessage, isNull);

      const failedResult = ScaffoldResult(
        success: false,
        errorMessage: 'Path traversal attempt rejected',
      );
      expect(failedResult.success, isFalse);
      expect(failedResult.errorMessage, equals('Path traversal attempt rejected'));
    });

    test('OrchestratorState awaitingStep2Confirmation flag works accurately', () {
      const state = OrchestratorState(
        status: WorkflowExecutionStatus.paused,
        awaitingStep2Confirmation: true,
        currentOperation: 'Step 1 complete: Project files scaffolded',
      );

      expect(state.awaitingStep2Confirmation, isTrue);
      expect(state.status, equals(WorkflowExecutionStatus.paused));

      final updated = state.copyWith(awaitingStep2Confirmation: false);
      expect(updated.awaitingStep2Confirmation, isFalse);
    });
  });
}
