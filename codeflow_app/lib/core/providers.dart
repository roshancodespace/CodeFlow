import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/companion_info.dart';
import '../models/project.dart';
import '../services/bluetooth_hid_service.dart';
import '../services/companion_api_service.dart';
import '../services/companion_discovery_service.dart';
import '../services/file_transfer_service.dart';
import '../services/project_manager_service.dart';
import '../services/typing_cadence_engine.dart';
import '../workflows/orchestrator_controller.dart';
import 'storage/local_storage_service.dart';

// --- Shared Preferences & Storage Provider ---
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Initialize sharedPreferencesProvider in main()');
});

final localStorageProvider = Provider<LocalStorageService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return LocalStorageService(prefs);
});

// --- Theme Mode State ---
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final LocalStorageService _storage;

  ThemeModeNotifier(this._storage) : super(_loadInitialMode(_storage));

  static ThemeMode _loadInitialMode(LocalStorageService storage) {
    switch (storage.themeMode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    String modeStr = 'system';
    if (mode == ThemeMode.light) modeStr = 'light';
    if (mode == ThemeMode.dark) modeStr = 'dark';
    await _storage.setThemeMode(modeStr);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  final storage = ref.watch(localStorageProvider);
  return ThemeModeNotifier(storage);
});

// --- Services Providers ---
final hidServiceProvider = Provider<IBluetoothHidService>((ref) {
  final service = BluetoothHidService();
  ref.onDispose(() => service.dispose());
  return service;
});

final companionApiProvider = Provider<CompanionApiService>((ref) {
  final service = CompanionApiService();
  ref.onDispose(() => service.dispose());
  return service;
});

final fileTransferServiceProvider = Provider<FileTransferService>((ref) {
  final service = FileTransferService();
  ref.onDispose(() => service.dispose());
  return service;
});

final discoveryServiceProvider = Provider<CompanionDiscoveryService>((ref) {
  final api = ref.watch(companionApiProvider);
  return CompanionDiscoveryService(apiService: api);
});

final cadenceEngineProvider = Provider<TypingCadenceEngine>((ref) {
  final hid = ref.watch(hidServiceProvider);
  final storage = ref.watch(localStorageProvider);
  final engine = TypingCadenceEngine(
    hidService: hid,
    config: CadenceConfig(
      targetCps: storage.typingSpeedCps,
      focusDelaySeconds: storage.focusDelaySeconds,
      newlinePauseMs: storage.newlinePauseMs,
      humanJitterEnabled: storage.humanJitterEnabled,
    ),
  );
  ref.onDispose(() => engine.dispose());
  return engine;
});

final projectManagerProvider = Provider<ProjectManagerService>((ref) {
  final storage = ref.watch(localStorageProvider);
  final service = ProjectManagerService(storage: storage);
  ref.onDispose(() => service.dispose());
  return service;
});

// --- Projects State Notifier ---
class ProjectsNotifier extends StateNotifier<List<Project>> {
  final LocalStorageService _storage;
  final ProjectManagerService _manager;

  ProjectsNotifier(this._storage, this._manager) : super([]) {
    loadProjects();
  }

  void loadProjects() {
    final list = _storage.getProjects();
    state = list;
  }

  Future<void> addProject(Project project) async {
    await _storage.saveProject(project);
    loadProjects();
  }

  Future<void> deleteProject(String id) async {
    await _storage.deleteProject(id);
    loadProjects();
  }

  Future<Project> createSampleProject() async {
    final p = await _manager.createSampleProject();
    loadProjects();
    return p;
  }
}

final projectsProvider =
    StateNotifierProvider<ProjectsNotifier, List<Project>>((ref) {
  final storage = ref.watch(localStorageProvider);
  final manager = ref.watch(projectManagerProvider);
  return ProjectsNotifier(storage, manager);
});

final selectedProjectProvider = StateProvider<Project?>((ref) => null);

// --- Orchestrator Provider ---
final orchestratorProvider =
    ChangeNotifierProvider<OrchestratorController>((ref) {
  final hid = ref.watch(hidServiceProvider);
  final api = ref.watch(companionApiProvider);
  final transfer = ref.watch(fileTransferServiceProvider);
  final cadence = ref.watch(cadenceEngineProvider);
  final storage = ref.watch(localStorageProvider);

  return OrchestratorController(
    hidService: hid,
    companionApi: api,
    fileTransferService: transfer,
    cadenceEngine: cadence,
    storage: storage,
  );
});

// --- Companion Host Status Provider ---
class CompanionStatusState {
  final bool isConnected;
  final CompanionInfo? info;
  final int? pingMs;
  final String? error;

  const CompanionStatusState({
    this.isConnected = false,
    this.info,
    this.pingMs,
    this.error,
  });
}

class CompanionStatusNotifier extends StateNotifier<CompanionStatusState> {
  final CompanionApiService _api;
  final LocalStorageService _storage;

  CompanionStatusNotifier(this._api, this._storage)
      : super(const CompanionStatusState()) {
    checkConnection();
  }

  Future<void> checkConnection() async {
    final host = _storage.companionHost;
    final port = _storage.companionPort;
    final token = _storage.companionToken;

    final isHealthy = await _api.checkHealth(host: host, port: port);
    if (!isHealthy) {
      state = const CompanionStatusState(
        isConnected: false,
        error: 'Companion offline or unreachable',
      );
      return;
    }

    final ping = await _api.measurePingLatency(host: host, port: port);
    final info = await _api.getInfo(host: host, port: port, token: token);

    state = CompanionStatusState(
      isConnected: true,
      info: info,
      pingMs: ping,
    );
  }
}

final companionStatusProvider =
    StateNotifierProvider<CompanionStatusNotifier, CompanionStatusState>((ref) {
  final api = ref.watch(companionApiProvider);
  final storage = ref.watch(localStorageProvider);
  return CompanionStatusNotifier(api, storage);
});
